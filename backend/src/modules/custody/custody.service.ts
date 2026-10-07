import {
  Injectable,
  ConflictException,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service.js';
import { Decimal } from '@prisma/client/runtime/library';
import * as bcrypt from 'bcryptjs';

// ── DTOs ─────────────────────────────────────────────────────────────────

export interface InitiateTransferDto {
  companyId: string;
  idempotencyKey: string;
  fromCustodianId: string;
  toCustodianId: string;
  fromWalletId?: string;
  toWalletId?: string;
  amount: number;
  fee?: number;
  channel?: string;
  paymentMethod?: string;
  notes?: string;
  metadata?: any;
}

// ── Service ──────────────────────────────────────────────────────────────

@Injectable()
export class CustodyService {
  private transferMetadata = new Map<
    string,
    { fee: number; channel: string; baseAmount: number }
  >();

  constructor(private readonly prisma: PrismaService) {}

  /**
   * POST /custody/transfers
   * Initiates a pending custody transfer. No balance changes until confirmed.
   */
  async initiateTransfer(dto: InitiateTransferDto) {
    // Idempotency check
    const existing = await this.prisma.custodyTransfer.findUnique({
      where: { idempotencyKey: dto.idempotencyKey },
    });
    if (existing) {
      return existing;
    }

    // 1. Fetch sender custodian by ID directly
    const senderCustodian = await this.prisma.custodianAccount.findUnique({
      where: { id: dto.fromCustodianId },
      include: { company: true },
    });

    if (!senderCustodian) {
      throw new BadRequestException('Unable to complete handover. Sender account could not be found.');
    }

    // 3. Operational company is naturally the custodian wallet's company
    const operationalCompanyId = senderCustodian.companyId;

    // Fetch original requested recipient custodian to understand who they are
    const originalToCustodian = await this.prisma.custodianAccount.findUnique({
      where: { id: dto.toCustodianId },
    });
    if (!originalToCustodian || !originalToCustodian.linkedUserId) {
      throw new BadRequestException('Unable to complete handover. Recipient account could not be resolved.');
    }

    const receiverUserId = originalToCustodian.linkedUserId;

    // 4. Resolve / Auto-heal recipient custodian under the operational company
    let receiverCustodian = await this.prisma.custodianAccount.findFirst({
      where: {
        linkedUserId: receiverUserId,
        companyId: operationalCompanyId,
      },
    });

    if (!receiverCustodian) {
      // If recipient doesn't have a custodian account in this concern yet, auto-create it
      receiverCustodian = await this.prisma.custodianAccount.create({
        data: {
          linkedUserId: receiverUserId,
          companyId: operationalCompanyId,
          name: originalToCustodian.name,
          type: 'person',
        },
      });
    }

    if (senderCustodian.id === receiverCustodian.id) {
      throw new ConflictException('Unable to complete handover. Cannot transfer to the same account.');
    }

    let fromWalletId = dto.fromWalletId || dto.metadata?.fromWalletId || dto.metadata?.walletId;
    const feeVal = Number(dto.fee || dto.metadata?.fee || 0);

    if (fromWalletId) {
      const wallet = await this.prisma.wallet.findUnique({
        where: { id: fromWalletId },
      });
      if (!wallet || wallet.custodianId !== dto.fromCustodianId) {
        throw new NotFoundException(
          `Unable to complete handover. Wallet is invalid or does not belong to your account.`,
        );
      }

      // Compute balance of sender wallet to validate balance >= amount + fee
      const movements = await this.prisma.moneyMovement.findMany({
        where: { walletId: fromWalletId },
        select: { direction: true, amount: true, fee: true },
      });
      let totalIn = 0, totalOut = 0, totalFees = 0;
      for (const m of movements) {
        const amt = Number(m.amount);
        const fee = m.fee ? Number(m.fee) : 0;
        if (m.direction === 'in') totalIn += amt;
        else if (m.direction === 'out') totalOut += amt;
        totalFees += fee;
      }
      const currentBalance = totalIn - totalOut - totalFees;
      const totalNeeded = dto.amount + feeVal;
      if (currentBalance < totalNeeded) {
        throw new BadRequestException(
          `Ensure you have sufficient balance (Available: ৳${currentBalance.toFixed(2)}, Required: ৳${totalNeeded.toFixed(2)}).`,
        );
      }
    }

    const channelVal = String(dto.channel || dto.paymentMethod || dto.metadata?.paymentMethod || dto.metadata?.channel || 'cash');

    // Transfer amount stored on CustodyTransfer must strictly be baseAmount
    const created = await this.prisma.custodyTransfer.create({
      data: {
        idempotencyKey: dto.idempotencyKey,
        fromCustodianId: senderCustodian.id,
        toCustodianId: receiverCustodian.id,
        fromWalletId: fromWalletId ?? null,
        toWalletId: dto.toWalletId ?? null,
        amount: new Decimal(dto.amount),
        fee: feeVal > 0 ? new Decimal(feeVal) : null,
        notes: dto.notes ?? null,
        metadata: {
          companyId: operationalCompanyId,
          walletId: fromWalletId ?? null,
          walletName: senderCustodian?.name || 'Cash in Hand',
          paymentMethod: channelVal || 'Physical Cash',
          fee: Number(feeVal || 0),
          note: dto.notes || (dto as any).note || '',
          ...(typeof dto.metadata === 'object' && dto.metadata !== null ? dto.metadata : {}),
        },
        status: 'pending',
      },
    });

    const meta = { fee: feeVal, channel: channelVal, baseAmount: dto.amount };
    this.transferMetadata.set(created.id, meta);
    this.transferMetadata.set(dto.idempotencyKey, meta);

    const receiptNo = `HND-${created.id.substring(0, 8).toUpperCase()}`;

    return {
      ...created,
      receiptNo,
      fee: feeVal,
      channel: channelVal,
      metadata: meta,
    };
  }

  /**
   * POST /custody/transfers/:id/confirm
   * Receiver confirms acceptance. Status becomes 'confirmed'.
   */
  async confirmTransfer(transferId: string, toWalletId?: string) {
    const transfer = await this.prisma.custodyTransfer.findUnique({
      where: { id: transferId },
    });
    if (!transfer) {
      throw new NotFoundException("Unable to complete handover. Transfer could not be found.");
    }
    if (transfer.status === 'confirmed') {
      return transfer; // already confirmed — idempotent
    }
    if (transfer.status === 'disputed') {
      throw new ConflictException('Cannot confirm a disputed transfer');
    }

    let targetToWalletId = toWalletId || transfer.toWalletId || null;
    if (!targetToWalletId) {
      const defaultWallet =
        (await this.prisma.wallet.findFirst({
          where: { custodianId: transfer.toCustodianId, isDefault: true, isArchived: false },
        })) ||
        (await this.prisma.wallet.findFirst({
          where: { custodianId: transfer.toCustodianId, isArchived: false },
        }));
      targetToWalletId = defaultWallet?.id || null;
    }

    const meta =
      this.transferMetadata.get(transfer.id) ||
      this.transferMetadata.get(transfer.idempotencyKey);
    const feeVal = meta?.fee || (transfer.fee ? Number(transfer.fee) : 0);
    const channelVal = meta?.channel || 'cash';

    const fromCustodian = await this.prisma.custodianAccount.findUnique({
      where: { id: transfer.fromCustodianId },
      select: { companyId: true, name: true, linkedUserId: true, linkedUser: { select: { id: true, name: true, designation: true } } },
    });

    const toCustodian = await this.prisma.custodianAccount.findUnique({
      where: { id: transfer.toCustodianId },
      select: { companyId: true, name: true, linkedUserId: true, linkedUser: { select: { id: true, name: true, designation: true } } },
    });

    const senderName = fromCustodian?.linkedUser?.name || fromCustodian?.name || 'Sender Custodian';
    const recipientName = toCustodian?.linkedUser?.name || toCustodian?.name || 'Recipient Custodian';
    const receiptNo = `HND-${transfer.id.substring(0, 8).toUpperCase()}`;

    const updated = await this.prisma.$transaction(async (tx) => {
      const updatedTransfer = await tx.custodyTransfer.update({
        where: { id: transferId },
        data: {
          status: 'confirmed',
          toWalletId: targetToWalletId,
          confirmedAt: new Date(),
        },
      });

      // Sender Outflow Movement
      await tx.moneyMovement.create({
        data: {
          idempotencyKey: crypto.randomUUID(),
          direction: 'out',
          amount: transfer.amount,
          fee: feeVal > 0 ? new Decimal(feeVal) : null,
          currency: 'BDT',
          channel: channelVal,
          custodianId: transfer.fromCustodianId,
          collectorId: fromCustodian?.linkedUserId || transfer.fromCustodianId,
          walletId: transfer.fromWalletId || null,
          entryTag: 'handover_out',
          notes: transfer.notes || `Handover sent to ${recipientName}`,
          metadata: {
            transferId: transfer.id,
            voucherNumber: receiptNo,
            recipientName: recipientName,
            paymentMethod: channelVal || 'Physical Cash',
            movementType: 'Cash Out',
            baseAmount: Number(transfer.amount),
            fee: feeVal,
          },
          occurredAt: new Date(),
          syncStatus: 'synced',
        },
      });

      // Recipient Inflow Movement
      await tx.moneyMovement.create({
        data: {
          idempotencyKey: crypto.randomUUID(),
          direction: 'in',
          amount: transfer.amount,
          fee: null,
          currency: 'BDT',
          channel: channelVal,
          custodianId: transfer.toCustodianId,
          collectorId: toCustodian?.linkedUserId || transfer.toCustodianId,
          walletId: targetToWalletId,
          entryTag: 'handover_in',
          notes: transfer.notes || `Handover received from ${senderName}`,
          metadata: {
            transferId: transfer.id,
            voucherNumber: receiptNo,
            senderName: senderName,
            paymentMethod: channelVal || 'Physical Cash',
            movementType: 'Cash In',
            baseAmount: Number(transfer.amount),
            fee: 0,
          },
          occurredAt: new Date(),
          syncStatus: 'synced',
        },
      });

      return updatedTransfer;
    });

    console.log('[Handover Confirm] Created movements for sender and receiver:', transfer.id);

    return {
      ...updated,
      receiptNo,
      fee: feeVal,
      channel: channelVal,
      metadata: meta || { baseAmount: Number(transfer.amount), fee: feeVal, channel: channelVal },
    };
  }

  /**
   * POST /custody/transfers/:id/dispute
   * Receiver flags discrepancy. Status becomes 'disputed'.
   */
  async disputeTransfer(transferId: string) {
    const transfer = await this.prisma.custodyTransfer.findUnique({
      where: { id: transferId },
    });
    if (!transfer) {
      throw new NotFoundException("Unable to complete handover. Transfer could not be found.");
    }
    if (transfer.status === 'confirmed') {
      throw new ConflictException('Cannot dispute a confirmed transfer');
    }
    if (transfer.status === 'disputed') {
      return transfer; // already disputed — idempotent
    }

    return this.prisma.custodyTransfer.update({
      where: { id: transferId },
      data: { status: 'disputed' },
    });
  }

  /**
   * Helper to ensure colleague accounts exist in the company so users can select them as recipients.
   */
  async ensureColleaguesExist(companyId: string) {
    // DISABLED: Auto-seeding colleagues is prohibited by "Zero Ghost Data" policy.
    return;
  }

  /**
   * GET /custody/custodians
   * Returns all custodian accounts for the company.
   */
  async getCustodians(companyId?: string) {
    try {
      const uuidRegex =
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
      let targetCompanyId =
        companyId && uuidRegex.test(companyId) ? companyId : undefined;

      if (!targetCompanyId) {
        const firstCompany = await this.prisma.company.findFirst();
        if (firstCompany) {
          targetCompanyId = firstCompany.id;
        }
      }

      if (!targetCompanyId) {
        return [];
      }

      // Ensure company has colleagues seeded for handovers
      await this.ensureColleaguesExist(targetCompanyId);

      const list = await this.prisma.custodianAccount.findMany({
        where: { companyId: targetCompanyId },
        include: {
          linkedUser: {
            select: { id: true, name: true, role: true, designation: true, department: true },
          },
        },
      });

      return list.map((c) => ({
        id: c.id,
        name: c.linkedUser?.name || c.name,
        designation: c.linkedUser?.designation || undefined,
        department: c.linkedUser?.department || undefined,
        type: c.type,
        companyId: c.companyId,
        linkedUser: c.linkedUser,
      }));
    } catch (err) {
      console.error('[CUSTODY SERVICE] getCustodians error:', err);
      return [];
    }
  }

  async getPendingTransfers(custodianId?: string, reqUser?: any) {
    const userId = reqUser?.id || reqUser?.sub;
    let userCustodianIds: string[] = [];
    if (custodianId) {
      userCustodianIds.push(custodianId);
    }
    if (userId) {
      const custodians = await this.prisma.custodianAccount.findMany({
        where: { linkedUserId: userId },
        select: { id: true },
      });
      userCustodianIds.push(...custodians.map(c => c.id));
    }
    const whereClause: any = { status: 'pending' };
    if (userCustodianIds.length > 0) {
      whereClause.OR = [
        { fromCustodianId: { in: userCustodianIds } },
        { toCustodianId: { in: userCustodianIds } },
      ];
    }
    const pending = await this.prisma.custodyTransfer.findMany({
      where: whereClause,
      include: {
        fromCustodian: { select: { id: true, name: true, linkedUser: { select: { id: true, name: true, role: true } } } },
        toCustodian: { select: { id: true, name: true, linkedUser: { select: { id: true, name: true, role: true } } } },
      },
      orderBy: { requestedAt: 'desc' },
    });
    return pending.map(t => {
      const meta = this.transferMetadata.get(t.id) || this.transferMetadata.get(t.idempotencyKey) || (typeof t.metadata === 'object' ? t.metadata : {});
      return {
        ...t,
        metadata: meta,
      };
    });
  }


  /**
   * GET /custody/notifications?custodianId=...&companyId=...
   *
   * Returns:
   *   a) Pending handover requests where to_custodian_id == custodianId
   *   b) Recent IN/OUT movement activity logs for this custodian
   */
  async getNotifications(custodianId: string, companyId: string) {
    // 1. Pending transfers directed TO this custodian
    const pendingTransfers = await this.prisma.custodyTransfer.findMany({
      where: {
        toCustodianId: custodianId,
        status: 'pending',
      },
      include: {
        fromCustodian: {
          select: {
            id: true,
            name: true,
            linkedUser: { select: { id: true, name: true, role: true } },
          },
        },
        toCustodian: {
          select: {
            id: true,
            name: true,
            linkedUser: { select: { id: true, name: true, role: true } },
          },
        },
      },
      orderBy: { requestedAt: 'desc' },
    });

    // 2. Recent movements for this custodian (last 50)
    const recentMovements = await this.prisma.moneyMovement.findMany({
      where: {
        custodianId,
        editedFromId: null, // exclude correction originals
      },
      orderBy: { createdAt: 'desc' },
      take: 50,
      include: {
        collector: { select: { id: true, name: true } },
      },
    });

    const enrichedPendingTransfers = pendingTransfers.map((t) => {
      const meta =
        this.transferMetadata.get(t.id) ||
        this.transferMetadata.get(t.idempotencyKey);
      const receiptNo = `HND-${t.id.substring(0, 8).toUpperCase()}`;
      return {
        ...t,
        receiptNo,
        fee: meta?.fee ?? 0,
        channel: meta?.channel ?? 'cash',
        metadata: {
          baseAmount: Number(t.amount),
          fee: meta?.fee ?? 0,
          channel: meta?.channel ?? 'cash',
        },
      };
    });

    return {
      pendingTransfers: enrichedPendingTransfers,
      recentMovements,
    };
  }

  async getTransfers(custodianId: string) {
    if (
      !custodianId ||
      custodianId === 'undefined' ||
      custodianId === 'null' ||
      typeof custodianId !== 'string' ||
      custodianId.trim() === ''
    ) {
      return [];
    }

    // Validate UUID format to prevent Prisma query errors
    const uuidRegex =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(custodianId)) {
      console.warn(
        '[CUSTODY SERVICE] getTransfers invalid custodianId format:',
        custodianId,
      );
      return [];
    }

    try {
      // Plain query — no nested includes to avoid Prisma relation errors.
      // Includes were removed because they previously crashed with a 500
      // when linkedUser.email or other invalid relation properties were
      // referenced. The response is still enriched by joining in-memory.
      const transfers = await this.prisma.custodyTransfer.findMany({
        where: {
          OR: [
            { fromCustodianId: custodianId },
            { toCustodianId: custodianId },
          ],
        },
        include: {
          fromCustodian: {
            select: {
              id: true,
              name: true,
              linkedUser: { select: { id: true, name: true, role: true, designation: true } },
            },
          },
          toCustodian: {
            select: {
              id: true,
              name: true,
              linkedUser: { select: { id: true, name: true, role: true, designation: true } },
            },
          },
        },
        orderBy: { requestedAt: 'desc' },
      });
      return transfers.map((t) => {
        const meta =
          this.transferMetadata.get(t.id) ||
          this.transferMetadata.get(t.idempotencyKey);
        const receiptNo = `HND-${t.id.substring(0, 8).toUpperCase()}`;
        return {
          ...t,
          receiptNo,
          fee: meta?.fee ?? 0,
          channel: meta?.channel ?? 'cash',
          metadata: {
            baseAmount: Number(t.amount),
            fee: meta?.fee ?? 0,
            channel: meta?.channel ?? 'cash',
          },
        };
      });
    } catch (err) {
      console.error('[CUSTODY SERVICE] getTransfers error:', err);
      return [];
    }
  }

}