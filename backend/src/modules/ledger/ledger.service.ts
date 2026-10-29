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
  categoryId?: string;
  ledgerId?: string;
  segmentId?: string;
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
  categoryId?: string;
  ledgerId?: string;
  segmentId?: string;
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

      // 1. Resolve Ledger ID (default to GEN-OPS if not provided)
      let effectiveLedgerId = dto.ledgerId || undefined;
      if (!effectiveLedgerId) {
        let tenantId: string | null = null;
        if (custodian.companyId) {
          const comp = await this.prisma.company.findUnique({
            where: { id: custodian.companyId },
            select: { tenantId: true },
          });
          tenantId = comp?.tenantId ?? null;
        }
        if (!tenantId && dto.collectorId) {
          const user = await this.prisma.user.findUnique({
            where: { id: dto.collectorId },
            select: { tenantId: true },
          });
          tenantId = user?.tenantId ?? null;
        }
        if (tenantId) {
          const defaultLedger = await this.ensureDefaultLedger(tenantId);
          effectiveLedgerId = defaultLedger?.id;
        }
      }

      // 2. Safely Resolve Segment ID
      let effectiveSegmentId: string | null = null;
      const rawSegment =
        dto.segmentId ||
        (dto as any).segment ||
        (dto as any).category ||
        null;

      if (rawSegment && effectiveLedgerId) {
        // Check if rawSegment is already a valid UUID existing in the Segment table
        const existingSegment = await this.prisma.segment.findFirst({
          where: {
            id: rawSegment,
            ledgerId: effectiveLedgerId,
          },
        });

        if (existingSegment) {
          effectiveSegmentId = existingSegment.id;
        } else {
          // rawSegment might be a name (e.g. "Client Payment") or a legacy Category ID
          let segmentName = rawSegment as string;

          // If it looks like a UUID, try resolving from the TransactionCategory table
          const legacyCategory =
            await this.prisma.transactionCategory.findUnique({
              where: { id: rawSegment },
            }).catch(() => null);   // gracefully handle non-UUID strings

          if (legacyCategory) {
            segmentName = legacyCategory.name;
          }

          // Find or create the Segment under this ledger with that name
          let resolvedSeg = await this.prisma.segment.findFirst({
            where: {
              ledgerId: effectiveLedgerId,
              name: { equals: segmentName.trim(), mode: 'insensitive' },
            },
          });

          if (!resolvedSeg) {
            resolvedSeg = await this.prisma.segment.create({
              data: {
                ledgerId: effectiveLedgerId,
                name: segmentName.trim(),
              },
            });
          }

          effectiveSegmentId = resolvedSeg.id;
        }
      }

      // Resolve a valid category/segment ID to satisfy foreign key constraint
      let validCategoryId: string | null = null;
      const requestedCat = (dto as any).categoryId || (dto as any).segmentId || (dto as any).categoryName || (dto as any).segmentName;

      if (requestedCat) {
        let tenantId: string | null = null;
        if (custodian.companyId) {
          const comp = await this.prisma.company.findUnique({
            where: { id: custodian.companyId },
            select: { tenantId: true },
          });
          tenantId = comp?.tenantId ?? null;
        }

        // 1. Try finding by ID
        let existingCat = await this.prisma.transactionCategory.findUnique({
          where: { id: requestedCat },
        }).catch(() => null);

        // 2. Try finding by name in this company
        if (!existingCat && custodian.companyId) {
          existingCat = await this.prisma.transactionCategory.findFirst({
            where: {
              companyId: custodian.companyId,
              name: { equals: requestedCat, mode: 'insensitive' },
            },
          }).catch(() => null);
        }

        // 3. If it does not exist, auto-create it on the fly!
        if (!existingCat && custodian.companyId && tenantId) {
          try {
            existingCat = await this.prisma.transactionCategory.create({
              data: {
                companyId: custodian.companyId,
                tenantId: tenantId,
                name: requestedCat,
                type: dirVal === 'in' ? 'INFLOW' : 'OUTFLOW',
              },
            });
          } catch (_) {}
        }

        if (existingCat) {
          validCategoryId = existingCat.id;
        }
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
          categoryId: validCategoryId ?? dto.categoryId ?? null,
          ledgerId: effectiveLedgerId || null,
          segmentId: effectiveSegmentId,
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

    // Resolve ledger — prefer dto, fall back to original
    const correctionLedgerId = dto.ledgerId ?? original.ledgerId;

    // Safely resolve segment just like recordMoneyMovement
    let correctionSegmentId: string | null = original.segmentId;
    const rawSeg =
      dto.segmentId ||
      (dto as any).segment ||
      (dto as any).category ||
      null;

    if (rawSeg && correctionLedgerId) {
      const existingSeg = await this.prisma.segment.findFirst({
        where: { id: rawSeg, ledgerId: correctionLedgerId },
      });

      if (existingSeg) {
        correctionSegmentId = existingSeg.id;
      } else {
        let segName = rawSeg as string;

        const legacyCat = await this.prisma.transactionCategory
          .findUnique({ where: { id: rawSeg } })
          .catch(() => null);

        if (legacyCat) {
          segName = legacyCat.name;
        }

        let resolved = await this.prisma.segment.findFirst({
          where: {
            ledgerId: correctionLedgerId,
            name: { equals: segName.trim(), mode: 'insensitive' },
          },
        });

        if (!resolved) {
          resolved = await this.prisma.segment.create({
            data: {
              ledgerId: correctionLedgerId,
              name: segName.trim(),
            },
          });
        }

        correctionSegmentId = resolved.id;
      }
    }

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
        categoryId: dto.categoryId ?? original.categoryId,
        ledgerId: correctionLedgerId,
        segmentId: correctionSegmentId,
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

  // ── Ledgers Governance Methods ──────────────────────────────────────

  async ensureDefaultLedger(tenantId: string) {
    let defaultLedger = await this.prisma.ledger.findFirst({
      where: { tenantId, code: 'GEN-OPS' },
      include: { segments: true },
    });
    if (!defaultLedger) {
      defaultLedger = await this.prisma.ledger.create({
        data: {
          tenantId,
          name: 'General Operations',
          code: 'GEN-OPS',
          description: 'Default system ledger for general operations',
          isPerpetual: true,
          status: 'ACTIVE',
        },
        include: { segments: true },
      });
    }
    return defaultLedger;
  }

  async getMyLedgers(reqUser: any) {
    const tenantId = reqUser?.tenantId || reqUser?.tenant_id;
    if (!tenantId) throw new BadRequestException('Tenant ID required');

    // Always find or ensure default General Operations ledger
    const defaultLedger = await this.ensureDefaultLedger(tenantId);

    // Find ledgers assigned to this user
    const assignedLedgers = await this.prisma.ledger.findMany({
      where: {
        tenantId,
        status: { not: 'ARCHIVED' },
        code: { not: 'GEN-OPS' },
        OR: [
          { assignments: { some: { userId: reqUser.id } } },
          ...(reqUser.role === 'SUITE_ADMIN' || reqUser.role === 'MANAGER'
            ? [{ assignments: { none: { role: 'MANAGER' } } }]
            : []),
        ],
      },
      include: { segments: true },
      orderBy: { createdAt: 'desc' },
    });

    const allLedgers = defaultLedger ? [defaultLedger, ...assignedLedgers] : assignedLedgers;
    return { success: true, ledgers: allLedgers };
  }
  async getLedgersForUser(userId: string, user?: any) {
    const companyId = user?.companyId;
    const ledgers = await this.prisma.ledger.findMany({
      where: companyId ? { companyId } : {},
      include: {
        segments: true,
        movements: {
          select: {
            id: true,
            amount: true,
            direction: true,
            type: true,
            categoryId: true,
            createdAt: true,
          },
        },
      },
    });

    return ledgers.map((l) => {
      let inflow = 0;
      let outflow = 0;
      for (const m of l.movements || []) {
        const amt = Number(m.amount) || 0;
        if (m.direction === 'in' || m.type === 'INFLOW') {
          inflow += amt;
        } else {
          outflow += amt;
        }
      }
      return {
        ...l,
        netBalance: inflow - outflow,
        totalInflow: inflow,
        totalOutflow: outflow,
      };
    });
  }

  async assignEmployeesToLedger(ledgerId: string, employeeUserIds: string[], managerUserId: string, reqUser: any) {
    const tenantId = reqUser?.tenantId || reqUser?.tenant_id;
    const ledger = await this.prisma.ledger.findFirst({
      where: { id: ledgerId, tenantId },
      include: { assignments: true },
    });
    if (!ledger) throw new NotFoundException('Ledger not found');

    const isSuite = reqUser?.role === 'SUITE_ADMIN';
    if (!isSuite) {
      const isAssignedManager = ledger.assignments.some(
        (a) => a.userId === managerUserId && a.role === 'MANAGER',
      );
      if (!isAssignedManager) {
        throw new BadRequestException('You are not assigned as a manager to this ledger.');
      }
    }

    // Remove existing employee assignments for this ledger
    await this.prisma.ledgerMember.deleteMany({
      where: { ledgerId, role: 'EMPLOYEE' },
    });

    if (Array.isArray(employeeUserIds) && employeeUserIds.length > 0) {
      await this.prisma.ledgerMember.createMany({
        data: employeeUserIds.map((userId) => ({
          ledgerId,
          userId,
          role: 'EMPLOYEE',
        })),
      });
    }

    const updated = await this.prisma.ledger.findUnique({
      where: { id: ledgerId },
      include: {
        assignments: {
          include: { user: { select: { id: true, name: true, handle: true, role: true } } },
        },
      },
    });

    return { success: true, ledger: updated };
  }

  async getSuiteLedgers(reqUser: any, search?: string, status?: string) {
    const tenantId = reqUser?.tenantId;
    if (!tenantId) throw new BadRequestException('Tenant ID required');

    await this.ensureDefaultLedger(tenantId);

    const where: any = { tenantId };
    if (status && status !== 'ALL' && status.trim() !== '') {
      where.status = status.toUpperCase();
    }

    if (search && search.trim().length > 0) {
      const q = search.trim();
      where.OR = [
        { name: { contains: q, mode: 'insensitive' } },
        { code: { contains: q, mode: 'insensitive' } },
      ];
    }

    const ledgers = await this.prisma.ledger.findMany({
      where,
      include: {
        assignments: {
          include: { user: { select: { id: true, name: true, handle: true } } },
        },
        segments: { select: { id: true, name: true } },
        movements: { select: { amount: true, direction: true } },
      },
      orderBy: { createdAt: 'desc' },
    });

    const serialized = ledgers.map((l) => {
      let inflow = 0;
      let outflow = 0;
      for (const m of l.movements) {
        const amt = Number(m.amount || 0);
        if (m.direction === 'in') inflow += amt;
        else if (m.direction === 'out') outflow += amt;
      }

      const managers = l.assignments
        .filter((a) => a.role === 'MANAGER')
        .map((a) => ({
          id: a.user.id,
          name: a.user.name,
          handle: a.user.handle,
        }));

      return {
        id: l.id,
        name: l.name,
        code: l.code,
        description: l.description || '',
        isPerpetual: l.isPerpetual,
        startDate: l.startDate?.toISOString() || null,
        endDate: l.endDate?.toISOString() || null,
        status: l.status,
        segmentsCount: l.segments.length,
        managersCount: managers.length,
        managers: managers,
        inflow: inflow,
        outflow: outflow,
        netVelocity: inflow - outflow,
      };
    });

    serialized.sort((a, b) => {
      if (a.code === 'GEN-OPS') return -1;
      if (b.code === 'GEN-OPS') return 1;
      return 0;
    });

    return { success: true, ledgers: serialized };
  }

  async createLedger(reqUser: any, dto: any) {
    const tenantId = reqUser?.tenantId;
    if (!tenantId) throw new BadRequestException('Tenant ID required');

    const name = dto.name?.trim();
    if (!name) throw new BadRequestException('Ledger name is required.');

    let code = dto.code ? dto.code.trim().toUpperCase() : '';
    if (!code) {
      code = name
        .toUpperCase()
        .replace(/[^A-Z0-9]/g, '_')
        .slice(0, 16);
      if (!code) code = `LEDGER_${Date.now().toString().slice(-4)}`;
    }

    const existing = await this.prisma.ledger.findFirst({
      where: { tenantId, code },
    });
    if (existing) {
      code = `${code}_${Date.now().toString().slice(-4)}`;
    }

    const rawManagerIds = dto.managerUserIds || dto.managerIds;
    const managerUserIds: string[] = Array.isArray(rawManagerIds)
      ? rawManagerIds.filter(Boolean)
      : [];

    const ledger = await this.prisma.ledger.create({
      data: {
        tenantId,
        companyId: dto.companyId || null,
        name,
        code,
        description: dto.description || null,
        isPerpetual: dto.isPerpetual ?? true,
        startDate: dto.startDate ? new Date(dto.startDate) : null,
        endDate: dto.endDate ? new Date(dto.endDate) : null,
        status: dto.status || 'ACTIVE',
        assignments: {
          create: managerUserIds.map((userId) => ({
            userId,
            role: 'MANAGER',
          })),
        },
      },
      include: {
        assignments: {
          include: { user: { select: { id: true, name: true, handle: true } } },
        },
      },
    });

    return { success: true, ledger };
  }

  async updateLedger(reqUser: any, ledgerId: string, dto: any) {
    const tenantId = reqUser?.tenantId;
    const ledger = await this.prisma.ledger.findFirst({
      where: { id: ledgerId, tenantId },
    });
    if (!ledger) {
      throw new NotFoundException('Ledger not found.');
    }

    const updateData: any = {};
    if (dto.name) updateData.name = dto.name.trim();
    if (dto.description !== undefined) updateData.description = dto.description;
    if (dto.status) updateData.status = dto.status;
    if (dto.isPerpetual !== undefined) updateData.isPerpetual = dto.isPerpetual;
    if (dto.startDate !== undefined) updateData.startDate = dto.startDate ? new Date(dto.startDate) : null;
    if (dto.endDate !== undefined) updateData.endDate = dto.endDate ? new Date(dto.endDate) : null;

    const rawManagerIds = dto.managerUserIds || dto.managerIds;
    if (Array.isArray(rawManagerIds)) {
      await this.prisma.ledgerMember.deleteMany({
        where: { ledgerId, role: 'MANAGER' },
      });
      if (rawManagerIds.length > 0) {
        await this.prisma.ledgerMember.createMany({
          data: rawManagerIds.map((userId: string) => ({
            ledgerId,
            userId,
            role: 'MANAGER',
          })),
        });
      }
    }

    const updated = await this.prisma.ledger.update({
      where: { id: ledgerId },
      data: updateData,
      include: {
        assignments: {
          include: { user: { select: { id: true, name: true, handle: true } } },
        },
      },
    });

    return { success: true, ledger: updated };
  }

  async deleteLedger(reqUser: any, ledgerId: string) {
    const tenantId = reqUser?.tenantId;
    const ledger = await this.prisma.ledger.findFirst({
      where: { id: ledgerId, tenantId },
    });
    if (!ledger) {
      throw new NotFoundException('Ledger not found.');
    }
    if (ledger.code === 'GEN-OPS') {
      throw new BadRequestException('The default General Operations ledger cannot be deleted.');
    }

    const movementCount = await this.prisma.moneyMovement.count({
      where: { ledgerId },
    });

    if (movementCount > 0) {
      const archived = await this.prisma.ledger.update({
        where: { id: ledgerId },
        data: { status: 'ARCHIVED' },
      });
      return { success: true, ledger: archived };
    }

    await this.prisma.ledgerMember.deleteMany({ where: { ledgerId } });
    await this.prisma.ledger.delete({ where: { id: ledgerId } });
    return { success: true, message: 'Ledger deleted successfully' };
  }

  async getManagerLedgers(reqUser: any) {
    return this.getMyLedgers(reqUser);
  }

  async getLedgerDetails(reqUser: any, ledgerId: string) {
    const ledger = await this.prisma.ledger.findFirst({
      where: { id: ledgerId },
      include: {
        assignments: {
          include: { user: { select: { id: true, name: true, handle: true } } },
        },
        segments: {
          include: {
            movements: {
              include: {
                collector: {
                  select: {
                    id: true,
                    name: true,
                    companies: {
                      select: {
                        company: { select: { code: true } },
                      },
                      take: 1,
                    },
                  },
                },
              },
              orderBy: { createdAt: 'desc' },
            },
          },
        },
        movements: {
          include: {
            collector: {
              select: {
                id: true,
                name: true,
                companies: {
                  select: {
                    company: { select: { code: true } },
                  },
                  take: 1,
                },
              },
            },
          },
          orderBy: { createdAt: 'desc' },
        },
      },
    });

    if (!ledger) throw new NotFoundException('Ledger not found.');

    let totalInflow = 0;
    let totalOutflow = 0;
    for (const m of ledger.movements) {
      const amt = Number(m.amount || 0);
      const dir = (m.direction || '').toUpperCase();
      if (dir === 'IN') totalInflow += amt;
      else if (dir === 'OUT') totalOutflow += amt;
    }

    const mapMovement = (m: any) => {
      const isDirIn = (m.direction || '').toUpperCase() === 'IN';
      const meta = (m.metadata as any) || {};
      const companyCode =
        m.collector?.companies?.[0]?.company?.code || meta.companyCode || meta.senderCode || '';
      return {
        id: m.id,
        amount: Number(m.amount || 0),
        direction: isDirIn ? 'in' : 'out',
        notes: m.notes || meta.note || meta.notes || '',
        voucherNumber: m.receiptNo || meta.voucherNumber || '',
        collectorName: m.collector?.name || meta.actorName || 'Staff',
        companyCode: companyCode ? companyCode.toUpperCase() : '',
        createdAt: m.createdAt ? m.createdAt.toISOString() : new Date().toISOString(),
      };
    };

    const segmentsData = ledger.segments.map((seg) => {
      let inflow = 0;
      let outflow = 0;
      for (const m of seg.movements) {
        const amt = Number(m.amount || 0);
        const dir = (m.direction || '').toUpperCase();
        if (dir === 'IN') inflow += amt;
        else if (dir === 'OUT') outflow += amt;
      }

      const txns = seg.movements.map(mapMovement);

      return {
        id: seg.id,
        name: seg.name,
        description: seg.description || '',
        transactionCount: seg.movements.length,
        totalInflow: inflow,
        totalOutflow: outflow,
        netBalance: inflow - outflow,
        transactions: txns,
      };
    });

    // Group unassigned movements under a fallback item if any exist
    const unsegmented = ledger.movements.filter((m) => !m.segmentId);
    if (unsegmented.length > 0) {
      let uInflow = 0;
      let uOutflow = 0;
      for (const m of unsegmented) {
        const amt = Number(m.amount || 0);
        const dir = (m.direction || '').toUpperCase();
        if (dir === 'IN') uInflow += amt;
        else if (dir === 'OUT') uOutflow += amt;
      }
      segmentsData.push({
        id: 'general-head',
        name: 'General Operational Entries',
        description: 'Historical records without assigned segment',
        transactionCount: unsegmented.length,
        totalInflow: uInflow,
        totalOutflow: uOutflow,
        netBalance: uInflow - uOutflow,
        transactions: unsegmented.map(mapMovement),
      });
    }

    // Sort: active segments with transactions first, then alphabetically / by volume
    segmentsData.sort((a, b) => {
      if (b.transactionCount !== a.transactionCount) {
        return b.transactionCount - a.transactionCount;
      }
      return (b.totalInflow + b.totalOutflow) - (a.totalInflow + a.totalOutflow);
    });

    const managers = ledger.assignments
      .filter((a) => a.role === 'MANAGER')
      .map((a) => ({ id: a.user.id, name: a.user.name, handle: a.user.handle }));

    return {
      success: true,
      ledger: {
        id: ledger.id,
        name: ledger.name,
        code: ledger.code,
        description: ledger.description || '',
        status: ledger.status,
        isPerpetual: ledger.isPerpetual,
        startDate: ledger.startDate?.toISOString() || null,
        endDate: ledger.endDate?.toISOString() || null,
        totalInflow,
        totalOutflow,
        managers,
        segments: segmentsData,
      },
    };
  }

  async assignEmployeeToLedger(reqUser: any, ledgerId: string, employeeUserId: string) {
    const isSuite = reqUser.role === 'SUITE_ADMIN';
    if (!isSuite) {
      const assignment = await this.prisma.ledgerMember.findUnique({
        where: {
          ledgerId_userId: { ledgerId, userId: reqUser.id },
        },
      });
      if (!assignment || assignment.role !== 'MANAGER') {
        throw new BadRequestException('Unauthorized to assign employees to this ledger');
      }
    }

    const member = await this.prisma.ledgerMember.upsert({
      where: {
        ledgerId_userId: { ledgerId, userId: employeeUserId },
      },
      update: { role: 'EMPLOYEE' },
      create: {
        ledgerId,
        userId: employeeUserId,
        role: 'EMPLOYEE',
      },
    });

    return member;
  }

  async createSegmentInLedger(reqUser: any, ledgerId: string, dto: any) {
    const isSuite = reqUser.role === 'SUITE_ADMIN';
    if (!isSuite) {
      const assignment = await this.prisma.ledgerMember.findUnique({
        where: {
          ledgerId_userId: { ledgerId, userId: reqUser.id },
        },
      });
      if (!assignment || assignment.role !== 'MANAGER') {
        throw new BadRequestException('Unauthorized to create segments in this ledger');
      }
    }

    const segment = await this.prisma.segment.create({
      data: {
        ledgerId,
        name: dto.name,
        code: dto.code || null,
        description: dto.description || null,
      },
    });

    return segment;
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
