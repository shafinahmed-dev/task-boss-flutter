import {
  Injectable,
  ConflictException,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service.js';
import { Decimal } from '@prisma/client/runtime/library';

// ── DTOs ─────────────────────────────────────────────────────────────────

export interface RecordMovementDto {
  companyId: string;
  idempotencyKey: string; // UUID — client-generated for offline safety
  direction: 'in' | 'out';
  amount: number;
  currency?: string; // defaults to 'BDT'
  channel:
    | 'cash'
    | 'cheque'
    | 'bank'
    | 'rtgs'
    | 'npsb'
    | 'bkash'
    | 'nagad'
    | 'other';
  walletId?: string;
  paymentMethod?: string;
  photoUrl?: string;
  collectorId: string;
  custodianId: string;
  entryTag:
    | 'client_payment'
    | 'loan_received'
    | 'other_income'
    | 'business_expense'
    | 'personal_partner'
    | 'loan_given'
    | 'loan_repayment'
    | 'partner_funding'
    | 'partner_reimbursement';
  receiptNo?: string;
  digitalReceiptId?: string;
  clientId?: string;
  projectId?: string;
  loanId?: string;
  occurredAt: string; // ISO-8601
  syncStatus?: string;
  metadata?: Record<string, any>;
}

export interface EditMovementDto {
  /** All fields from RecordMovementDto except idempotencyKey —
   *  server generates a new idempotencyKey for the correction row. */
  direction?: 'in' | 'out';
  amount?: number;
  channel?: RecordMovementDto['channel'];
  photoUrl?: string;
  entryTag?: RecordMovementDto['entryTag'];
  receiptNo?: string;
  clientId?: string;
  projectId?: string;
  loanId?: string;
  occurredAt?: string;
}

export interface CustodianBalance {
  custodianId: string;
  totalIn: number;
  totalOut: number;
  confirmedTransferIn: number;
  confirmedTransferOut: number;
  netBalance: number;
}

// ── Inter-Company Cost Allocation DTO ────────────────────────────────────

export interface InterCompanyAllocationDto {
  /** The company that physically paid for the shared cost */
  sourceCompanyId: string;
  /** The company that owes its share of the cost */
  targetCompanyId: string;
  /** Amount to allocate from source to target */
  amount: number;
  /** Human-readable description of the shared cost */
  description: string;
  /** Client-generated idempotency key */
  idempotencyKey: string;
  /** Details of the primary OUT movement to record under source company */
  movement: Omit<RecordMovementDto, 'companyId' | 'idempotencyKey'>;
}

export interface InterCompanyAllocationResult {
  /** The primary OUT movement recorded under source company */
  sourceMovement: unknown;
  /** The InterCompanyAllocation record tracking the receivable/liability */
  allocation: unknown;
}

// ── Service ──────────────────────────────────────────────────────────────

@Injectable()
export class LedgerService {
  constructor(private readonly prisma: PrismaService) {}

  // ───────────────────────────────────────────────────────────────────────
  // getCustodianBalance
  //
  // Computes balance strictly on the fly.  No stored balance is ever read.
  //
  // Formula:
  //   netBalance =
  //     (Σ IN movements for this custodian)
  //     + (Σ confirmed incoming CustodyTransfers)
  //     − (Σ OUT movements for this custodian)
  //     − (Σ confirmed outgoing CustodyTransfers)
  //
  // Exclusion rules:
  //   • If a movement has been superseded (i.e. another row points to it
  //     via edited_from_id), the ORIGINAL row is excluded from the sum
  //     and only the latest revision counts.
  //   • This is achieved by excluding any row whose id appears as an
  //     edited_from_id in another row (the "superseded" set).
  // ───────────────────────────────────────────────────────────────────────

  async getCustodianBalance(
    custodianId: string,
    companyId: string,
  ): Promise<CustodianBalance> {
    // 1. Gather all superseded movement IDs (rows that have been edited)
    const supersededRows = await this.prisma.moneyMovement.findMany({
      where: { editedFromId: { not: null } },
      select: { editedFromId: true },
    });
    const supersededIds = new Set(
      supersededRows
        .map((r: { editedFromId: string | null }) => r.editedFromId)
        .filter(Boolean) as string[],
    );

    // 2. Compute movement totals (exclude superseded originals)
    const movementAgg = await this.prisma.moneyMovement.aggregate({
      where: {
        custodianId,
        // Exclude rows that have been superseded by an edit
        id: { notIn: Array.from(supersededIds) },
      },
      _sum: { amount: true },
      _count: true,
    });

    // Separate IN vs OUT via groupBy (aggregate can't filter by direction)
    const inGroup = await this.prisma.moneyMovement.groupBy({
      by: ['direction'],
      where: {
        custodianId,
        direction: 'in',
        id: { notIn: Array.from(supersededIds) },
      },
      _sum: { amount: true, fee: true },
    });

    const outGroup = await this.prisma.moneyMovement.groupBy({
      by: ['direction'],
      where: {
        custodianId,
        direction: 'out',
        id: { notIn: Array.from(supersededIds) },
      },
      _sum: { amount: true, fee: true },
    });

    const totalIn = this.extractSum(inGroup, 'in');
    const totalOut = this.extractSum(outGroup, 'out');

    // 3. Confirmed custody transfer totals
    const confirmedTransferIn =
      await this.prisma.custodyTransfer.aggregate({
        where: {
          toCustodianId: custodianId,
          status: 'confirmed',
        },
        _sum: { amount: true, fee: true },
      });

    const confirmedTransferOut =
      await this.prisma.custodyTransfer.aggregate({
        where: {
          fromCustodianId: custodianId,
          status: 'confirmed',
        },
        _sum: { amount: true, fee: true },
      });

    const transferIn = this.ToDecimal(confirmedTransferIn._sum.amount);
    const transferOutAmount = this.ToDecimal(confirmedTransferOut._sum.amount);
    const transferOutFee = this.ToDecimal(confirmedTransferOut._sum.fee);
    const transferOut = transferOutAmount + transferOutFee;

    const netBalance = totalIn + transferIn - totalOut - transferOut;

    return {
      custodianId,
      totalIn,
      totalOut,
      confirmedTransferIn: transferIn,
      confirmedTransferOut: transferOut,
      netBalance,
    };
  }

  // ───────────────────────────────────────────────────────────────────────
  // recordMoneyMovement
  //
  // • Idempotency: if the idempotency_key already exists, return the
  //   existing record instead of creating a duplicate.
  // • Append-only: every call INSERTs a new row.  No UPDATEs or DELETEs.
  // ───────────────────────────────────────────────────────────────────────

  async recordMoneyMovement(dto: RecordMovementDto) {
    try {
      // 1. Idempotency Key check & UUID normalization
      const uuidRegex =
        /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
      if (!dto.idempotencyKey || !uuidRegex.test(dto.idempotencyKey)) {
        dto.idempotencyKey = crypto.randomUUID();
      }

      // Idempotency check — return existing if key matches
      const existing = await this.prisma.moneyMovement.findUnique({
        where: { idempotencyKey: dto.idempotencyKey },
      });
      if (existing) {
        return existing;
      }

      // Validate custodian exists
      if (!dto.custodianId) {
        throw new BadRequestException('custodianId is required');
      }
      const custodian = await this.prisma.custodianAccount.findUnique({
        where: { id: dto.custodianId },
      });
      if (!custodian) {
        throw new NotFoundException('Custodian ' + dto.custodianId + ' not found');
      }

      // Validate collector exists or fallback to custodian linked user
      if (!dto.collectorId) {
        dto.collectorId = custodian.linkedUserId || dto.custodianId;
      } else {
        const collector = await this.prisma.user.findUnique({
          where: { id: dto.collectorId },
        });
        if (!collector) {
          if (custodian.linkedUserId) {
            dto.collectorId = custodian.linkedUserId;
          } else {
            throw new NotFoundException('Collector user ' + dto.collectorId + ' not found');
          }
        }
      }

      // Validate wallet if provided
      if (dto.walletId) {
        const wallet = await this.prisma.wallet.findUnique({
          where: { id: dto.walletId },
        });
        if (!wallet) {
          throw new NotFoundException(`Wallet ${dto.walletId} not found`);
        }
        if (wallet.custodianId !== dto.custodianId) {
          throw new BadRequestException(
            `Wallet ${dto.walletId} does not belong to custodian ${dto.custodianId}`,
          );
        }
      }

      const amountNum = Number(dto.amount);
      if (isNaN(amountNum) || amountNum <= 0) {
        throw new BadRequestException('Amount must be a positive number');
      }

      const dirVal = String(dto.direction || 'in').toLowerCase() as 'in' | 'out';
      const channelVal = String(dto.channel || 'cash').toLowerCase();

      const feeVal = Number(dto.metadata?.fee || (dto as any).fee || 0);
      const metadata = dto.metadata ? { ...dto.metadata } : {};
      if (dto.paymentMethod) {
        metadata.paymentMethod = dto.paymentMethod;
      }

      const movement = await this.prisma.moneyMovement.create({
        data: {
          fee: feeVal > 0 ? new Decimal(feeVal) : null,
          notes: (metadata.notes || metadata.note || (dto as any).notes || (dto as any).note) ?? null,
          metadata: Object.keys(metadata).length > 0 ? metadata : undefined,
          walletId: dto.walletId ?? null,
          idempotencyKey: dto.idempotencyKey,
          direction: dirVal,
          amount: new Decimal(amountNum),
          currency: dto.currency ?? 'BDT',
          channel: channelVal,
          photoUrl: dto.photoUrl ?? null,
          collectorId: dto.collectorId,
          custodianId: dto.custodianId,
          entryTag: dto.entryTag,
          receiptNo: dto.receiptNo ?? null,
          digitalReceiptId: dto.digitalReceiptId ?? null,
          clientId: dto.clientId ?? null,
          projectId: dto.projectId ?? null,
          loanId: dto.loanId ?? null,
          editedFromId: null,
          occurredAt: dto.occurredAt ? new Date(dto.occurredAt) : new Date(),
          syncStatus: dto.syncStatus ?? 'synced',
        },
      });

      return movement;
    } catch (err: any) {
      if (err instanceof BadRequestException || err instanceof NotFoundException) {
        throw err;
      }
      throw new BadRequestException('Failed to record movement: ' + err.message);
    }
  }

  async editMoneyMovement(
    movementId: string,
    dto: EditMovementDto,
  ) {
    const original = await this.prisma.moneyMovement.findUnique({
      where: { id: movementId },
    });
    if (!original) {
      throw new NotFoundException(`MoneyMovement ${movementId} not found`);
    }

    // Generate a fresh idempotency key for the correction row
    const correctionIdempotencyKey = crypto.randomUUID();

    const correction = await this.prisma.moneyMovement.create({
      data: {
        idempotencyKey: correctionIdempotencyKey,
        direction: dto.direction ?? original.direction,
        amount: new Decimal(dto.amount ?? Number(original.amount)),
        currency: original.currency,
        channel: dto.channel ?? original.channel,
        photoUrl: dto.photoUrl ?? original.photoUrl,
        collectorId: original.collectorId,
        custodianId: original.custodianId,
        entryTag: dto.entryTag ?? original.entryTag,
        receiptNo: dto.receiptNo ?? original.receiptNo,
        digitalReceiptId: original.digitalReceiptId,
        clientId: dto.clientId ?? original.clientId,
        projectId: dto.projectId ?? original.projectId,
        loanId: dto.loanId ?? original.loanId,
        editedFromId: movementId,
        occurredAt: new Date(
          dto.occurredAt ?? original.occurredAt.toISOString(),
        ),
        syncStatus: original.syncStatus,
      },
    });

    return correction;
  }

  // ───────────────────────────────────────────────────────────────────────
  // getCustodianMovements — paginated ledger history
  // ───────────────────────────────────────────────────────────────────────

  async getCustodianMovements(
    custodianId: string,
    opts: { page?: number; limit?: number; direction?: 'in' | 'out' },
  ) {
    const page = opts.page ?? 1;
    const limit = Math.min(opts.limit ?? 50, 200);
    const skip = (page - 1) * limit;

    const where: Record<string, unknown> = { custodianId };
    if (opts.direction) where.direction = opts.direction;

    const [items, total] = await Promise.all([
      this.prisma.moneyMovement.findMany({
        where,
        orderBy: { occurredAt: 'desc' },
        skip,
        take: limit,
      }),
      this.prisma.moneyMovement.count({ where }),
    ]);

    return {
      items,
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  private extractSum(
    group: { direction: string; _sum: { amount: Decimal | { toNumber(): number } | null, fee?: Decimal | { toNumber(): number } | null } }[],
    direction: string,
  ): number {
    const found = group.find((g) => g.direction === direction);
    if (!found) return 0;
    const amt = found._sum.amount ? this.ToDecimal(found._sum.amount) : 0;
    const feeVal = found._sum.fee ? this.ToDecimal(found._sum.fee) : 0;
    if (direction === 'out') {
      return amt + feeVal;       
    }
    return amt;
  }

  // ───────────────────────────────────────────────────────────────────────
  // allocateInterCompanyCost
  //
  // When a money movement represents a cross-entity shared cost (e.g.
  // equipment or material purchased by Company A for a project under
  // Company B), this handler:
  //
  //   1. Records the primary OUT movement under Company A.
  //   2. Automatically registers an offsetting inter-company
  //      liability / receivable entry between Company A and Company B.
  //   3. Ensures neither company's dynamic balance calculation breaks.
  //
  // The InterCompanyAllocation record tracks the amount owed by the
  // target company back to the source company. Settlement is tracked
  // via the `status` field (pending → settled).
  // ───────────────────────────────────────────────────────────────────────

  async allocateInterCompanyCost(
    dto: InterCompanyAllocationDto,
  ): Promise<InterCompanyAllocationResult> {
    // Idempotency check
    const existingAlloc = await this.prisma.interCompanyAllocation.findUnique({
      where: { idempotencyKey: dto.idempotencyKey },
    });
    if (existingAlloc) {
      return {
        sourceMovement: await this.prisma.moneyMovement.findUnique({
          where: { id: existingAlloc.sourceMovementId },
        }),
        allocation: existingAlloc,
      };
    }

    // Validate companies exist and are different
    if (dto.sourceCompanyId === dto.targetCompanyId) {
      throw new ConflictException(
        'Source and target companies must be different for inter-company allocation',
      );
    }

    const [sourceCompany, targetCompany] = await Promise.all([
      this.prisma.company.findUnique({ where: { id: dto.sourceCompanyId } }),
      this.prisma.company.findUnique({ where: { id: dto.targetCompanyId } }),
    ]);

    if (!sourceCompany) {
      throw new NotFoundException(
        `Source company ${dto.sourceCompanyId} not found`,
      );
    }
    if (!targetCompany) {
      throw new NotFoundException(
        `Target company ${dto.targetCompanyId} not found`,
      );
    }

    // Validate custodian belongs to source company
    const custodian = await this.prisma.custodianAccount.findUnique({
      where: { id: dto.movement.custodianId },
    });
    if (!custodian || custodian.companyId !== dto.sourceCompanyId) {
      throw new NotFoundException(
        `Custodian ${dto.movement.custodianId} not found in source company ${dto.sourceCompanyId}`,
      );
    }

    // 1. Record the primary OUT movement under source company
    const sourceMovement = await this.prisma.moneyMovement.create({
      data: {
        idempotencyKey: crypto.randomUUID(),
        direction: 'out',
        amount: new Decimal(dto.amount),
        currency: dto.movement.currency ?? 'BDT',
        channel: dto.movement.channel,
        photoUrl: dto.movement.photoUrl ?? null,
        collectorId: dto.movement.collectorId,
        custodianId: dto.movement.custodianId,
        entryTag: dto.movement.entryTag,
        receiptNo: dto.movement.receiptNo ?? null,
        digitalReceiptId: dto.movement.digitalReceiptId ?? null,
        clientId: dto.movement.clientId ?? null,
        projectId: dto.movement.projectId ?? null,
        loanId: dto.movement.loanId ?? null,
        editedFromId: null,
        occurredAt: new Date(dto.movement.occurredAt),
        syncStatus: dto.movement.syncStatus ?? 'synced',
      },
    });

    // 2. Register the inter-company allocation (liability/receivable)
    const allocation = await this.prisma.interCompanyAllocation.create({
      data: {
        idempotencyKey: dto.idempotencyKey,
        sourceCompanyId: dto.sourceCompanyId,
        targetCompanyId: dto.targetCompanyId,
        sourceMovementId: sourceMovement.id,
        amount: new Decimal(dto.amount),
        description: dto.description,
        status: 'pending',
      },
    });

    return { sourceMovement, allocation };
  }

  // ───────────────────────────────────────────────────────────────────────
  // settleInterCompanyAllocation
  //
  // Marks an inter-company allocation as settled when the target company
  // has reimbursed the source company.
  // ───────────────────────────────────────────────────────────────────────

  async settleInterCompanyAllocation(allocationId: string) {
    const allocation = await this.prisma.interCompanyAllocation.findUnique({
      where: { id: allocationId },
    });
    if (!allocation) {
      throw new NotFoundException(
        `InterCompanyAllocation ${allocationId} not found`,
      );
    }
    if (allocation.status === 'settled') {
      return allocation; // Already settled — idempotent
    }

    return this.prisma.interCompanyAllocation.update({
      where: { id: allocationId },
      data: { status: 'settled' },
    });
  }

  private ToDecimal(val: Decimal | { toNumber(): number } | null): number {
    if (!val) return 0;
    return typeof (val as any).toNumber === 'function'
      ? (val as { toNumber(): number }).toNumber()
      : new Decimal(val as unknown as string).toNumber();
  }
}
