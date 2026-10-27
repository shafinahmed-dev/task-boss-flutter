import {
  Injectable,
  ConflictException,
  NotFoundException,
  BadRequestException,
  ForbiddenException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service.js';
import { Decimal } from '@prisma/client/runtime/library';
import * as bcrypt from 'bcryptjs';
import * as crypto from 'crypto';

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
  private readonly logger = new Logger(CustodyService.name);
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
    if (!originalToCustodian) {
      throw new BadRequestException('Unable to complete handover. Recipient account could not be resolved.');
    }

    const receiverUserId = originalToCustodian.linkedUserId;

    // 4. Resolve / Auto-heal recipient custodian under the operational company
    let receiverCustodian: any;
    if (receiverUserId) {
      receiverCustodian = await this.prisma.custodianAccount.findFirst({
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
            type: originalToCustodian.type || 'person',
          },
        });
      }
    } else {
      receiverCustodian = originalToCustodian;
      if (originalToCustodian.companyId !== operationalCompanyId) {
        const existing = await this.prisma.custodianAccount.findFirst({
          where: {
            companyId: operationalCompanyId,
            name: originalToCustodian.name,
            type: originalToCustodian.type,
          },
        });
        if (existing) {
          receiverCustodian = existing;
        }
      }
    }

    if (senderCustodian.id === receiverCustodian.id) {
      throw new ConflictException('Unable to complete handover. Cannot transfer to the same account.');
    }

    // MANDATORY GUARD: Prevent self-handover
    const isSameUser =
      (receiverCustodian.linkedUserId && senderCustodian.linkedUserId && receiverCustodian.linkedUserId === senderCustodian.linkedUserId) ||
      (senderCustodian.linkedUserId && receiverUserId && senderCustodian.linkedUserId === receiverUserId) ||
      ((dto as any).recipientUserId && senderCustodian.linkedUserId === (dto as any).recipientUserId) ||
      senderCustodian.id === receiverCustodian.id;

    if (isSameUser) {
      throw new BadRequestException(
        'Self-handover is not permitted. You cannot transfer custody to yourself.',
      );
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
  async confirmTransfer(transferId: string, reqUser?: any, providedToWalletId?: string) {
    const transfer = await this.prisma.custodyTransfer.findUnique({
      where: { id: transferId },
      include: {
        fromCustodian: { include: { linkedUser: true } },
        toCustodian: { include: { linkedUser: true } },
      },
    });

    if (!transfer) {
      throw new NotFoundException("Unable to complete handover. Transfer could not be found.");
    }
    if (transfer.status === 'confirmed' || transfer.status === 'ACCEPTED' || transfer.status === 'accepted') {
      return { success: true, message: 'Transfer already confirmed', transfer };
    }
    if (transfer.status === 'disputed') {
      throw new ConflictException('Cannot confirm a disputed transfer');
    }

    const userId = reqUser?.id || reqUser?.sub;
    const operationalCompanyId =
      transfer.fromCustodian?.companyId ||
      transfer.toCustodian?.companyId ||
      (transfer.metadata as any)?.companyId;

    // Find current user's custodian account in this company
    let currentCustodian: any = null;
    if (userId) {
      currentCustodian = await this.prisma.custodianAccount.findFirst({
        where: {
          companyId: operationalCompanyId,
          linkedUserId: userId,
        },
        include: { linkedUser: true },
      });
      if (!currentCustodian) {
        currentCustodian = await this.prisma.custodianAccount.findFirst({
          where: {
            linkedUserId: userId,
          },
          include: { linkedUser: true },
        });
      }
    }

    // Resilient Recipient Ownership Check:
    // Allow accept if current user is either the linked user OR the custodian account
    const recipientUserId = transfer.toCustodian?.linkedUserId || (transfer.metadata as any)?.recipientUserId;
    const recipientCustodianId = transfer.toCustodianId;

    const isAuthorizedRecipient =
      !userId ||
      (recipientUserId && recipientUserId === userId) ||
      (recipientCustodianId && currentCustodian && recipientCustodianId === currentCustodian.id) ||
      (transfer.toCustodian?.linkedUserId === userId);

    if (userId && !isAuthorizedRecipient) {
      this.logger.error(
        `Unauthorized accept: user ${userId} tried to accept handover intended for custodian ${recipientCustodianId} / user ${recipientUserId}`,
      );
      throw new ForbiddenException('You are not authorized to accept this handover');
    }

    // Ensure recipient has a valid CustodianAccount
    let recipientCustodian: any = currentCustodian || transfer.toCustodian;

    if (!recipientCustodian && userId && operationalCompanyId) {
      recipientCustodian = await this.prisma.custodianAccount.create({
        data: {
          companyId: operationalCompanyId,
          linkedUserId: userId,
          name: reqUser?.name || 'Recipient User',
          type: (reqUser?.role || 'employee').toLowerCase(),
        },
        include: { linkedUser: true },
      });
    }

    // AUTO-RESOLVE DESTINATION WALLET:
    let destWallet: any = null;
    const destWalletId = providedToWalletId || transfer.toWalletId;
    if (destWalletId) {
      destWallet = await this.prisma.wallet.findUnique({
        where: { id: destWalletId },
      });
    }

    // Resolve recipient user ID
    const resolvedRecipientUserId = recipientUserId || userId;

    // Ensure destWallet resolves to the recipient's primary wallet ("Cash in Hand" with balance)
    if (resolvedRecipientUserId) {
      const primaryCashWallet = await this.prisma.wallet.findFirst({
        where: {
          custodian: { linkedUserId: resolvedRecipientUserId },
          type: 'CASH',
          isArchived: false,
          name: { equals: 'Cash in Hand', mode: 'insensitive' },
        },
        include: { custodian: true },
      });

      if (primaryCashWallet) {
        // Prefer the primary "Cash in Hand" wallet
        if (!destWallet || destWallet.name !== 'Cash in Hand') {
          destWallet = primaryCashWallet;
          if (primaryCashWallet.custodian) {
            recipientCustodian = primaryCashWallet.custodian;
          }
        }
      }
    }

    if (!destWallet && recipientCustodian) {
      destWallet = await this.prisma.wallet.findFirst({
        where: {
          custodianId: recipientCustodian.id,
          type: 'CASH',
          isArchived: false,
        },
        orderBy: [{ isDefault: 'desc' }, { createdAt: 'asc' }],
      });

      if (!destWallet && operationalCompanyId) {
        destWallet = await this.prisma.wallet.create({
          data: {
            companyId: operationalCompanyId,
            custodianId: recipientCustodian.id,
            name: 'Cash in Hand',
            type: 'CASH',
            isDefault: true,
          },
        });
      }
    }

    const targetToWalletId = destWallet?.id ?? null;

    const meta = typeof transfer.metadata === 'object' && transfer.metadata !== null ? transfer.metadata as any : {};
    const feeVal = Number(transfer.fee || meta.fee || 0);
    const channelVal = meta.channel || meta.paymentMethod || 'cash';

    const senderUser = transfer.fromCustodian?.linkedUser;
    const receiverUser = recipientCustodian?.linkedUser || reqUser;
    const receiptNo = meta.voucherNumber || `HND-${transfer.id.substring(0, 8).toUpperCase()}`;

    try {
      const result = await this.prisma.$transaction(async (tx) => {
        // 1. Mark handover as confirmed
        const updatedTransfer = await tx.custodyTransfer.update({
          where: { id: transferId },
          data: {
            status: 'confirmed',
            toCustodianId: recipientCustodian.id,
            toWalletId: targetToWalletId,
            confirmedAt: new Date(),
          },
        });

        // 2. Sender Outflow Movement
        await tx.moneyMovement.create({
          data: {
            idempotencyKey: crypto.randomUUID(),
            direction: 'out',
            amount: transfer.amount,
            fee: feeVal > 0 ? new Decimal(feeVal) : null,
            currency: 'BDT',
            channel: channelVal,
            custodianId: transfer.fromCustodianId,
            collectorId: transfer.fromCustodian?.linkedUserId || transfer.fromCustodianId,
            walletId: transfer.fromWalletId || null,
            entryTag: 'handover_out',
            notes: `Sent to ${receiverUser?.name || 'Staff'}`,
            metadata: {
              movementType: 'Handover Sent',
              transferId: transfer.id,
              voucherNumber: receiptNo,
              channel: channelVal,
              recipientName: receiverUser?.name || 'Staff',
              recipientUserId: receiverUser?.id || null,
              senderName: senderUser?.name || 'Sender',
              senderUserId: senderUser?.id || null,
            },
            occurredAt: new Date(),
            syncStatus: 'synced',
          },
        });

        // 3. Recipient Inflow Movement
        await tx.moneyMovement.create({
          data: {
            idempotencyKey: crypto.randomUUID(),
            direction: 'in',
            amount: transfer.amount,
            fee: 0,
            currency: 'BDT',
            channel: channelVal,
            custodianId: recipientCustodian.id,
            collectorId: recipientCustodian.linkedUserId || recipientCustodian.id,
            walletId: targetToWalletId,
            entryTag: 'handover_in',
            notes: `Received from ${senderUser?.name || 'Manager'}`,
            metadata: {
              movementType: 'Handover Received',
              transferId: transfer.id,
              voucherNumber: receiptNo,
              channel: channelVal,
              senderName: senderUser?.name || 'Sender',
              senderUserId: senderUser?.id || null,
              recipientName: receiverUser?.name || reqUser?.name || 'Recipient',
              recipientUserId: receiverUser?.id || reqUser?.id || null,
            },
            occurredAt: new Date(),
            syncStatus: 'synced',
          },
        });

        return updatedTransfer;
      });

      this.logger.log(`[Handover Confirm] Atomic acceptance complete for transfer: ${transferId}`);
      return { success: true, message: 'Handover accepted successfully', transfer: result };
    } catch (error) {
      this.logger.error(`Error processing atomic acceptance for handover ${transferId}:`, error);
      throw error;
    }
  }

  /**
   * Alias for confirmTransfer to support handover accept terminology
   */
  async acceptHandover(handoverId: string, reqUser?: any, dto?: { destinationWalletId?: string; toWalletId?: string }) {
    return this.confirmTransfer(handoverId, reqUser, dto?.destinationWalletId || dto?.toWalletId);
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
   * Cleans up duplicate 0-balance custodian accounts and ensures primary Cash in Hand wallet is restored.
   */
  async ensureColleaguesExist(companyId: string) {
    try {
      // Find all active company users (Managers AND Employees)
      const activeUsers = await this.prisma.user.findMany({
        where: {
          role: {
            in: ['MANAGER', 'EMPLOYEE', 'manager', 'employee'],
          },
        },
        include: {
          custodianAccounts: {
            include: {
              wallets: true,
            },
          },
        },
      });

      for (const u of activeUsers) {
        // 1. Identify primary custodian account (holds 'Cash in Hand' or has wallet movements)
        const primaryCustodian =
          u.custodianAccounts.find((ca) =>
            ca.wallets.some(
              (w) => w.name.toLowerCase() === 'cash in hand' && !w.isArchived,
            ),
          ) ||
          u.custodianAccounts.find((ca) => ca.wallets.length > 0) ||
          u.custodianAccounts[0];

        if (primaryCustodian) {
          // Explicitly ensure linkedUserId is attached to the primary custodian account
          if (primaryCustodian.linkedUserId !== u.id) {
            await this.prisma.custodianAccount.update({
              where: { id: primaryCustodian.id },
              data: { linkedUserId: u.id },
            });
          }

          // Clean up any empty duplicate custodian accounts & 0-balance duplicate wallets
          for (const duplicateAccount of u.custodianAccounts) {
            if (duplicateAccount.id === primaryCustodian.id) continue;

            const movementCount = await this.prisma.moneyMovement.count({
              where: { custodianId: duplicateAccount.id },
            });
            const transferCount = await this.prisma.custodyTransfer.count({
              where: {
                OR: [
                  { fromCustodianId: duplicateAccount.id },
                  { toCustodianId: duplicateAccount.id },
                ],
              },
            });

            if (movementCount === 0 && transferCount === 0) {
              await this.prisma.wallet.deleteMany({
                where: { custodianId: duplicateAccount.id },
              });
              await this.prisma.custodianAccount.delete({
                where: { id: duplicateAccount.id },
              });
            }
          }

          // Ensure the primary account has a genuine 'Cash in Hand' wallet with isDefault: true
          const cashInHandWallet = primaryCustodian.wallets.find(
            (w) => w.name.toLowerCase() === 'cash in hand' && !w.isArchived,
          );
          if (cashInHandWallet) {
            if (!cashInHandWallet.isDefault) {
              await this.prisma.wallet.update({
                where: { id: cashInHandWallet.id },
                data: { isDefault: true },
              });
            }
          } else {
            const firstCashWallet = primaryCustodian.wallets.find(
              (w) => w.type === 'CASH' && !w.isArchived,
            );
            if (firstCashWallet) {
              await this.prisma.wallet.update({
                where: { id: firstCashWallet.id },
                data: { name: 'Cash in Hand', isDefault: true },
              });
            } else {
              await this.prisma.wallet.create({
                data: {
                  custodianId: primaryCustodian.id,
                  companyId: primaryCustodian.companyId || companyId,
                  name: 'Cash in Hand',
                  type: 'CASH',
                  isDefault: true,
                },
              });
            }
          }
          continue;
        }

        // 2. If user has NO custodian account anywhere, create one
        let account = await this.prisma.custodianAccount.findFirst({
          where: {
            companyId,
            linkedUserId: u.id,
          },
        });

        if (!account) {
          account = await this.prisma.custodianAccount.findFirst({
            where: {
              companyId,
              name: u.name,
            },
          });

          if (account) {
            await this.prisma.custodianAccount.update({
              where: { id: account.id },
              data: {
                linkedUserId: u.id,
                type: u.role.toLowerCase(),
              },
            });
          } else {
            account = await this.prisma.custodianAccount.create({
              data: {
                companyId,
                linkedUserId: u.id,
                name: u.name,
                type: u.role.toLowerCase(),
              },
            });
          }
        }

        if (account) {
          const wallet = await this.prisma.wallet.findFirst({
            where: { custodianId: account.id, isArchived: false },
          });
          if (!wallet) {
            await this.prisma.wallet.create({
              data: {
                custodianId: account.id,
                companyId,
                name: 'Cash in Hand',
                type: 'CASH',
                isDefault: true,
              },
            });
          }
        }
      }
    } catch (err) {
      this.logger.error('ensureColleaguesExist error:', err);
    }
  }

  /**
   * Returns wallets for a custodian account or user, guaranteeing the primary
   * "Cash in Hand" wallet is returned as the default with accurate balance.
   */
  async getCustodianWallets(userIdOrCustodianId: string, companyId?: string) {
    this.logger.log(`Fetching wallets for identifier: ${userIdOrCustodianId}, companyId: ${companyId}`);
    if (!userIdOrCustodianId) return [];

    // 1. Find all custodian accounts associated with this user
    const custodianAccounts = await this.prisma.custodianAccount.findMany({
      where: {
        OR: [
          { id: userIdOrCustodianId },
          { linkedUserId: userIdOrCustodianId },
        ],
      },
    });

    const custodianIds = custodianAccounts.map((c) => c.id);
    if (custodianIds.length === 0) {
      custodianIds.push(userIdOrCustodianId);
    }

    // 2. Query all active wallets belonging to any of these custodian accounts
    let wallets = await this.prisma.wallet.findMany({
      where: {
        custodianId: { in: custodianIds },
        isArchived: false,
      },
      include: {
        custodian: true,
      },
    });

    // 3. Fallback: If no wallets found, look for ANY wallet linked to the user's name (e.g. "Cash in Hand")
    if (wallets.length === 0) {
      const user = await this.prisma.user.findFirst({
        where: {
          OR: [
            { id: userIdOrCustodianId },
            { id: custodianAccounts[0]?.linkedUserId || undefined },
          ],
        },
      });

      if (user) {
        // Find any existing "Cash in Hand" wallet for this user or their name
        wallets = await this.prisma.wallet.findMany({
          where: {
            OR: [
              { name: { contains: 'Cash', mode: 'insensitive' } },
              { name: { contains: user.name, mode: 'insensitive' } },
            ],
            isArchived: false,
          },
          include: {
            custodian: true,
          },
        });

        // If still none, ensure one primary Cash in Hand wallet is created
        if (wallets.length === 0 && custodianAccounts.length > 0) {
          const primaryCustodian = custodianAccounts[0];
          const newWallet = await this.prisma.wallet.create({
            data: {
              companyId: primaryCustodian.companyId,
              custodianId: primaryCustodian.id,
              name: 'Cash in Hand',
              type: 'CASH',
              isDefault: true,
            },
            include: {
              custodian: true,
            },
          });
          wallets = [newWallet];
        }
      }
    }

    this.logger.log(`Found ${wallets.length} wallets for ${userIdOrCustodianId}`);

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
          balance: Math.max(0, currentBalance),
        };
      }),
    );

    // Prioritize "Cash in Hand" as default
    walletsWithBalance.sort((a, b) => {
      const aIsCashInHand = a.name.toLowerCase() === 'cash in hand';
      const bIsCashInHand = b.name.toLowerCase() === 'cash in hand';
      if (aIsCashInHand && !bIsCashInHand) return -1;
      if (!aIsCashInHand && bIsCashInHand) return 1;
      if (a.isDefault && !b.isDefault) return -1;
      if (!a.isDefault && b.isDefault) return 1;
      return 0;
    });

    return walletsWithBalance;
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
        where: {
          OR: [
            { companyId: targetCompanyId },
            { linkedUser: { companies: { some: { companyId: targetCompanyId } } } },
          ],
          type: { not: 'company' },
          linkedUserId: { not: null },
          linkedUser: {
            role: { not: 'SYSTEM' },
          },
        },
        include: {
          linkedUser: {
            select: { id: true, name: true, role: true, designation: true, department: true },
          },
          wallets: true,
        },
      });

      // Deduplicate by linkedUserId, keeping the primary custodian account
      const custodianByUser = new Map<string, (typeof list)[0]>();
      for (const acc of list) {
        const uId = acc.linkedUserId;
        if (!uId) continue;
        const existing = custodianByUser.get(uId);
        if (!existing) {
          custodianByUser.set(uId, acc);
        } else {
          // If the new one has 'Cash in Hand' wallet, prioritize it
          const hasCashInHand = acc.wallets.some(
            (w) => w.name.toLowerCase() === 'cash in hand',
          );
          if (hasCashInHand) {
            custodianByUser.set(uId, acc);
          }
        }
      }

      const deduplicatedList = Array.from(custodianByUser.values());

      // Clean in-memory filtering: remove any root or system accounts
      const eligibleCustodians = deduplicatedList.filter((acc) => {
        const name = (acc.name || '').toLowerCase();
        const role = (acc.linkedUser?.role || '').toUpperCase();
        return !name.includes('root') && role !== 'SYSTEM';
      });

      const mapped = eligibleCustodians.map((c) => {
        const role = c.linkedUser?.role || '';
        const isManager =
          role.toUpperCase() === 'MANAGER' || role.toUpperCase() === 'SUITE_ADMIN';
        return {
          id: c.id,
          name: c.linkedUser?.name || c.name,
          designation: c.linkedUser?.designation || undefined,
          department: c.linkedUser?.department || undefined,
          type: c.type,
          companyId: c.companyId,
          role: role || undefined,
          isManager,
          linkedUser: c.linkedUser,
        };
      });

      mapped.sort((a, b) => {
        if (a.isManager && !b.isManager) return -1;
        if (!a.isManager && b.isManager) return 1;
        return (a.name || '').localeCompare(b.name || '');
      });

      return mapped;
    } catch (err) {
      console.error('[CUSTODY SERVICE] getCustodians error:', err);
      return [];
    }
  }

  async getPendingTransfers(reqUser: any) {
    const userId = reqUser?.id || reqUser?.sub;
    const custodianIds: string[] = [];
    if (userId) {
      const custodians = await this.prisma.custodianAccount.findMany({
        where: { linkedUserId: userId },
        select: { id: true },
      });
      custodianIds.push(...custodians.map(c => c.id));
    }

    // 2. Fetch both pending and recently resolved transfers for this user
    const transfers = await this.prisma.custodyTransfer.findMany({
      where: {
        OR: custodianIds.length > 0 ? [
          { fromCustodianId: { in: custodianIds } },
          { toCustodianId: { in: custodianIds } },
        ] : undefined,
      },
      include: {
        fromCustodian: {
          include: {
            linkedUser: { select: { id: true, name: true, handle: true, role: true } },
          },
        },
        toCustodian: {
          include: {
            linkedUser: { select: { id: true, name: true, handle: true, role: true } },
          },
        },
      },
      orderBy: { requestedAt: 'desc' },
      take: 30,
    });

    const pendingList = [];
    const auditList = [];

    for (const t of transfers) {
      const meta = (t.metadata as any) || {};
      const isSender = custodianIds.includes(t.fromCustodianId) || t.fromCustodian?.linkedUserId === userId;
      const senderName = t.fromCustodian?.linkedUser?.name || t.fromCustodian?.name || meta.senderName || 'Sender';
      const receiverName = t.toCustodian?.linkedUser?.name || t.toCustodian?.name || meta.recipientName || 'Receiver';
      const channel = meta.paymentMethod || meta.channel || 'Physical Cash';
      const voucher = meta.voucherNumber || 'HND-TRANSFER';

      const item = {
        id: t.id,
        amount: Number(t.amount || 0),
        fee: Number(t.fee || 0),
        status: t.status,
        voucherNumber: voucher,
        channel: channel,
        note: t.notes || meta.note || '',
        isSender,
        isIncoming: !isSender,
        direction: isSender ? 'out' : 'in',
        senderName,
        receiverName,
        declinedBy: meta.declinedBy || null,
        cancelledBy: meta.cancelledBy || null,
        createdAt: (t.confirmedAt || t.requestedAt || new Date()).toISOString(),
      };

      if (t.status === 'pending') {
        pendingList.push(item);
      } else if (t.status === 'declined' || t.status === 'cancelled') {
        auditList.push({
          ...item,
          title: t.status === 'declined' ? 'Handover Declined' : 'Handover Cancelled',
        });
      }
    }

    return {
      success: true,
      transfers: pendingList,
      resolvedTransfers: auditList,
    };
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

  async cancelTransfer(id: string, reqUser: any) {
    const transfer = await this.prisma.custodyTransfer.findUnique({
      where: { id },
      include: { fromCustodian: true },
    });

    if (!transfer) {
      throw new BadRequestException('Transfer record not found.');
    }

    if (transfer.status !== 'pending') {
      throw new BadRequestException(`Transfer cannot be cancelled because it is already ${transfer.status}.`);
    }

    const meta = (transfer.metadata as any) || {};
    const isSender =
      transfer.fromCustodian?.linkedUserId === reqUser.id ||
      meta.senderUserId === reqUser.id ||
      reqUser.role === 'SUITE_ADMIN';

    if (!isSender) {
      throw new ForbiddenException('Only the sender can cancel this handover.');
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.custodyTransfer.update({
        where: { id },
        data: {
          status: 'cancelled',
          confirmedAt: new Date(),
          metadata: {
            ...meta,
            cancelledBy: reqUser.name,
            cancelledAt: new Date().toISOString(),
          },
        },
      });
    });

    return { success: true, message: 'Handover cancelled successfully.' };
  }

  async declineTransfer(id: string, reqUser: any) {
    const transfer = await this.prisma.custodyTransfer.findUnique({
      where: { id },
      include: { toCustodian: true },
    });

    if (!transfer) {
      throw new BadRequestException('Transfer record not found.');
    }

    if (transfer.status !== 'pending') {
      throw new BadRequestException(`Transfer cannot be declined because it is already ${transfer.status}.`);
    }

    const meta = (transfer.metadata as any) || {};
    const isReceiver =
      transfer.toCustodian?.linkedUserId === reqUser.id ||
      meta.receiverUserId === reqUser.id ||
      meta.recipientUserId === reqUser.id ||
      reqUser.role === 'SUITE_ADMIN';

    if (!isReceiver) {
      throw new ForbiddenException('Only the intended recipient can decline this handover.');
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.custodyTransfer.update({
        where: { id },
        data: {
          status: 'declined',
          confirmedAt: new Date(),
          metadata: {
            ...meta,
            declinedBy: reqUser.name,
            declinedByUserId: reqUser.id,
            declinedAt: new Date().toISOString(),
          },
        },
      });
    });

    return { success: true, message: 'Handover declined.' };
  }

}