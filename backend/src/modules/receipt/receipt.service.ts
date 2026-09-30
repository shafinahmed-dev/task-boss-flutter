import {
  Injectable,
  ConflictException,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service.js';

// ── DTOs ─────────────────────────────────────────────────────────────────

export interface AssignBlockDto {
  companyId: string;
  assignedToUserId: string;
  prefix: string;
  rangeStart: number;
  rangeEnd: number;
}

export interface IssueReceiptDto {
  companyId: string;
  moneyMovementId: string;
  linkedPhysicalReceiptNo?: string;
  clientCopySentAt?: string;
}

// ── Service ──────────────────────────────────────────────────────────────

@Injectable()
export class ReceiptService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * POST /receipts/blocks/assign
   * Admin assigns a numbered receipt block to a collector/user.
   */
  async assignBlock(dto: AssignBlockDto) {
    if (dto.rangeStart >= dto.rangeEnd) {
      throw new BadRequestException('rangeStart must be less than rangeEnd');
    }

    // Validate user exists in the company
    const userCompany = await this.prisma.userCompany.findUnique({
      where: {
        userId_companyId: {
          userId: dto.assignedToUserId,
          companyId: dto.companyId,
        },
      },
    });
    if (!userCompany) {
      throw new NotFoundException(
        `User ${dto.assignedToUserId} not found in company ${dto.companyId}`,
      );
    }

    // Check for overlapping blocks with same prefix in the same company
    const overlapping = await this.prisma.receiptNumberBlock.findFirst({
      where: {
        companyId: dto.companyId,
        prefix: dto.prefix,
        status: 'active',
        OR: [
          {
            rangeStart: { lte: dto.rangeEnd },
            rangeEnd: { gte: dto.rangeStart },
          },
        ],
      },
    });

    if (overlapping) {
      throw new ConflictException(
        `Overlapping block exists: ${overlapping.prefix}#${overlapping.rangeStart}–${overlapping.rangeEnd}`,
      );
    }

    return this.prisma.receiptNumberBlock.create({
      data: {
        companyId: dto.companyId,
        assignedToUserId: dto.assignedToUserId,
        prefix: dto.prefix,
        rangeStart: dto.rangeStart,
        rangeEnd: dto.rangeEnd,
        currentPointer: dto.rangeStart,
        status: 'active',
      },
    });
  }

  /**
   * POST /receipts/issue
   * Auto-increments the pointer in the active block and issues a
   * DigitalReceipt linked to a money_movement.
   */
  async issueReceipt(dto: IssueReceiptDto) {
    // Find the active block for this user+company
    const block = await this.prisma.receiptNumberBlock.findFirst({
      where: {
        companyId: dto.companyId,
        status: 'active',
      },
      orderBy: { createdAt: 'desc' },
    });

    if (!block) {
      throw new NotFoundException('No active receipt block for this company');
    }

    if (block.currentPointer >= block.rangeEnd) {
      throw new ConflictException(
        `Receipt block ${block.prefix}#${block.rangeStart}–${block.rangeEnd} is exhausted`,
      );
    }

    const receiptNumber = `${block.prefix}-${String(block.currentPointer).padStart(6, '0')}`;

    // Check money movement exists and isn't already linked to a receipt
    const movement = await this.prisma.moneyMovement.findUnique({
      where: { id: dto.moneyMovementId },
    });
    if (!movement) {
      throw new NotFoundException(`MoneyMovement ${dto.moneyMovementId} not found`);
    }
    if (movement.digitalReceiptId) {
      throw new ConflictException(
        `MoneyMovement ${dto.moneyMovementId} already has a receipt`,
      );
    }

    // Create the receipt first (get the ID), then update in a transaction
    const receipt = await this.prisma.digitalReceipt.create({
      data: {
        receiptNumber,
        blockId: block.id,
        moneyMovementId: dto.moneyMovementId,
        companyId: dto.companyId,
        linkedPhysicalReceiptNo: dto.linkedPhysicalReceiptNo ?? null,
        clientCopySentAt: dto.clientCopySentAt
          ? new Date(dto.clientCopySentAt)
          : null,
      },
    });

    await this.prisma.$transaction([
      this.prisma.receiptNumberBlock.update({
        where: { id: block.id },
        data: {
          currentPointer: { increment: 1 },
          status: block.currentPointer + 1 >= block.rangeEnd ? 'exhausted' : 'active',
        },
      }),
      this.prisma.moneyMovement.update({
        where: { id: dto.moneyMovementId },
        data: {
          digitalReceiptId: receipt.id,
          receiptNo: receiptNumber,
        },
      }),
    ]);

    return receipt;
  }
}