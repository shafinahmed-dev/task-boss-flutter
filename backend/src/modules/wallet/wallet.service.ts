import {
  Injectable,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service.js';
import { Decimal } from '@prisma/client/runtime/library';
import { WalletType } from '@prisma/client';

export interface CreateWalletDto {
  custodianId?: string;
  companyId?: string;
  name: string;
  type: WalletType;
  accountNumber?: string;
  institution?: string;
  isDefault?: boolean;
  initialBalance?: number;
}

export interface WalletTransferDto {
  fromWalletId: string;
  toWalletId: string;
  amount: number;
  fee?: number;
  note?: string;
}

export interface UpdateWalletDto {
  name?: string;
  institution?: string;
  accountNumber?: string;
  isDefault?: boolean;
}

@Injectable()
export class WalletService {
  constructor(private readonly prisma: PrismaService) {}

  async getWallets(custodianId: string) {
    let wallets = await this.prisma.wallet.findMany({
      where: { custodianId, isArchived: false },
      orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }],
    });

    if (wallets.length === 0 && custodianId) {
      const custodian = await this.prisma.custodianAccount.findUnique({
        where: { id: custodianId },
      });
      if (custodian) {
        const defaultWallet = await this.prisma.wallet.create({
          data: {
            custodianId: custodian.id,
            companyId: custodian.companyId,
            name: 'Cash in Hand',
            type: WalletType.CASH,
            isDefault: true,
          },
        });
        wallets = [defaultWallet];
      }
    }

    const supersededRows = await this.prisma.moneyMovement.findMany({
      where: { editedFromId: { not: null } },
      select: { editedFromId: true },
    });
    const supersededIds = new Set(
      supersededRows
        .map((r) => r.editedFromId)
        .filter(Boolean) as string[],
    );

    const walletsWithBalance = await Promise.all(
      wallets.map(async (wallet) => {
        const movements = await this.prisma.moneyMovement.findMany({
          where: {
            walletId: wallet.id,
            id: { notIn: Array.from(supersededIds) },
          },
          select: {
            direction: true,
            amount: true,
            fee: true,
          },
        });

        let totalIn = 0;
        let totalOut = 0;
        let totalFees = 0;

        for (const m of movements) {
          const amt = Number(m.amount);
          const fee = m.fee ? Number(m.fee) : 0;
          if (m.direction === 'in') {
            totalIn += amt;
          } else if (m.direction === 'out') {
            totalOut += amt;
          }
          totalFees += fee;
        }

        const currentBalance = totalIn - totalOut - totalFees;

        return {
          ...wallet,
          currentBalance: Math.max(0, currentBalance),
        };
      }),
    );

    return walletsWithBalance;
  }
  async createWallet(dto: CreateWalletDto, userId: string) {
    let custodianId = dto.custodianId;
    let companyId = dto.companyId;

    if (!custodianId) {
      const custodian = await this.prisma.custodianAccount.findFirst({
        where: { linkedUserId: userId },
      });
      if (!custodian) {
        throw new NotFoundException(`No custodian account found for user ${userId}`);
      }
      custodianId = custodian.id;
      companyId = custodian.companyId;
    } else if (!companyId) {
      const custodian = await this.prisma.custodianAccount.findUnique({
        where: { id: custodianId },
      });
      if (!custodian) {
        throw new NotFoundException(`Custodian ${custodianId} not found`);
      }
      companyId = custodian.companyId;
    }

    if (!dto.name || !dto.name.trim()) {
      throw new BadRequestException('Wallet name is required');
    }

    return this.prisma.$transaction(async (tx) => {
      if (dto.isDefault) {
        await tx.wallet.updateMany({
          where: { custodianId },
          data: { isDefault: false },
        });
      }

      const newWallet = await tx.wallet.create({
        data: {
          custodianId,
          companyId,
          name: dto.name.trim(),
          type: dto.type || WalletType.CASH,
          accountNumber: dto.accountNumber ?? null,
          institution: dto.institution ?? null,
          isDefault: dto.isDefault ?? false,
        },
      });

      const initBal = Number(dto.initialBalance || 0);
      if (initBal > 0) {
        await tx.moneyMovement.create({
          data: {
            idempotencyKey: crypto.randomUUID(),
            direction: 'in',
            amount: new Decimal(initBal),
            currency: 'BDT',
            channel: (dto.type || 'CASH').toLowerCase(),
            collectorId: userId,
            custodianId,
            walletId: newWallet.id,
            entryTag: 'opening_balance',
            notes: 'Opening Balance',
            occurredAt: new Date(),
            syncStatus: 'synced',
          },
        });
      }

      return {
        ...newWallet,
        currentBalance: initBal,
      };
    });
  }

  async transferBetweenWallets(dto: WalletTransferDto, userId: string) {
    if (!dto.fromWalletId || !dto.toWalletId) {
      throw new BadRequestException('fromWalletId and toWalletId are required');
    }
    if (dto.fromWalletId === dto.toWalletId) {
      throw new BadRequestException('Cannot transfer to the same wallet');
    }
    const transferAmount = Number(dto.amount);
    if (isNaN(transferAmount) || transferAmount <= 0) {
      throw new BadRequestException('Transfer amount must be positive');
    }

    const [fromWallet, toWallet] = await Promise.all([
      this.prisma.wallet.findUnique({ where: { id: dto.fromWalletId } }),
      this.prisma.wallet.findUnique({ where: { id: dto.toWalletId } }),
    ]);

    if (!fromWallet) {
      throw new NotFoundException(`Wallet ${dto.fromWalletId} not found`);
    }
    if (!toWallet) {
      throw new NotFoundException(`Wallet ${dto.toWalletId} not found`);
    }

    const feeAmt = Number(dto.fee || 0);

    return this.prisma.$transaction(async (tx) => {
      const outMovement = await tx.moneyMovement.create({
        data: {
          idempotencyKey: crypto.randomUUID(),
          direction: 'out',
          amount: new Decimal(transferAmount),
          fee: feeAmt > 0 ? new Decimal(feeAmt) : null,
          currency: 'BDT',
          channel: fromWallet.type.toLowerCase(),
          collectorId: userId,
          custodianId: fromWallet.custodianId,
          walletId: fromWallet.id,
          entryTag: 'internal_transfer',
          notes: dto.note || 'Internal Transfer',
          occurredAt: new Date(),
          syncStatus: 'synced',
          metadata: {
            transferType: 'internal_wallet_transfer',
            toWalletId: toWallet.id,
          },
        },
      });

      const inMovement = await tx.moneyMovement.create({
        data: {
          idempotencyKey: crypto.randomUUID(),
          direction: 'in',
          amount: new Decimal(transferAmount),
          currency: 'BDT',
          channel: toWallet.type.toLowerCase(),
          collectorId: userId,
          custodianId: toWallet.custodianId,
          walletId: toWallet.id,
          entryTag: 'internal_transfer',
          notes: dto.note || 'Internal Transfer',
          occurredAt: new Date(),
          syncStatus: 'synced',
          metadata: {
            transferType: 'internal_wallet_transfer',
            fromWalletId: fromWallet.id,
          },
        },
      });

      return {
        success: true,
        outMovement,
        inMovement,
      };
    });
  }

  async updateWallet(walletId: string, dto: UpdateWalletDto, userId?: string) {
    const wallet = await this.prisma.wallet.findUnique({
      where: { id: walletId },
    });
    if (!wallet || wallet.isArchived) {
      throw new NotFoundException(`Wallet ${walletId} not found`);
    }

    if (dto.isDefault) {
      await this.prisma.wallet.updateMany({
        where: { custodianId: wallet.custodianId, isDefault: true },
        data: { isDefault: false },
      });
    }

    const updated = await this.prisma.wallet.update({
      where: { id: walletId },
      data: {
        ...(dto.name !== undefined && { name: dto.name.trim() }),
        ...(dto.institution !== undefined && { institution: dto.institution.trim() }),
        ...(dto.accountNumber !== undefined && { accountNumber: dto.accountNumber.trim() }),
        ...(dto.isDefault !== undefined && { isDefault: dto.isDefault }),
      },
    });

    return updated;
  }

  async deleteWallet(walletId: string, userId?: string) {
    const wallet = await this.prisma.wallet.findUnique({
      where: { id: walletId },
    });
    if (!wallet) {
      throw new NotFoundException(`Wallet ${walletId} not found`);
    }

    // 1. Calculate current balance
    const supersededRows = await this.prisma.moneyMovement.findMany({
      where: { editedFromId: { not: null } },
      select: { editedFromId: true },
    });
    const supersededIds = new Set(
      supersededRows
        .map((r) => r.editedFromId)
        .filter(Boolean) as string[],
    );

    const movements = await this.prisma.moneyMovement.findMany({
      where: {
        walletId: wallet.id,
        id: { notIn: Array.from(supersededIds) },
      },
      select: { direction: true, amount: true, fee: true },
    });

    let totalIn = 0;
    let totalOut = 0;
    let totalFees = 0;

    for (const m of movements) {
      const amt = Number(m.amount);
      const fee = m.fee ? Number(m.fee) : 0;
      if (m.direction === 'in') {
        totalIn += amt;
      } else if (m.direction === 'out') {
        totalOut += amt;
      }
      totalFees += fee;
    }

    const currentBalance = totalIn - totalOut - totalFees;

    // Reject deletion if non-zero balance
    if (Math.abs(currentBalance) > 0.001) {
      throw new BadRequestException(
        'Cannot delete wallet with non-zero balance. Transfer funds first.',
      );
    }

    // Check if transactions exist for historical audit preservation
    const totalTransactions = await this.prisma.moneyMovement.count({
      where: { walletId: wallet.id },
    });

    if (totalTransactions > 0) {
      // Soft-delete / Archive
      await this.prisma.wallet.update({
        where: { id: wallet.id },
        data: { isArchived: true, isDefault: false },
      });
      return {
        success: true,
        archived: true,
        message: 'Wallet archived successfully (historical transactions preserved).',
      };
    } else {
      // Hard delete
      await this.prisma.wallet.delete({
        where: { id: wallet.id },
      });
      return {
        success: true,
        archived: false,
        message: 'Wallet deleted successfully.',
      };
    }
  }
}