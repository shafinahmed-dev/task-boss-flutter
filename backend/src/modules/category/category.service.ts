import { Injectable, NotFoundException, BadRequestException, ConflictException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service.js';

@Injectable()
export class CategoryService {
  constructor(private prisma: PrismaService) {}

  async getCategories(companyId: string, type?: string) {
    const where: any = { companyId };
    if (type && type.trim() !== '') {
      const upperType = type.toUpperCase();
      where.OR = [
        { type: upperType },
        { type: 'BOTH' },
      ];
    }
    return this.prisma.transactionCategory.findMany({
      where,
      orderBy: { name: 'asc' },
    });
  }

  async createCategory(tenantId: string, companyIds: string[], dto: { name: string; type?: string; companyId: string }) {
    if (!dto.companyId || !companyIds.includes(dto.companyId)) {
      throw new BadRequestException('Invalid or unauthorized companyId');
    }
    const name = dto.name?.trim();
    if (!name) {
      throw new BadRequestException('Category name is required');
    }
    const type = (dto.type || 'BOTH').toUpperCase();
    if (!['INFLOW', 'OUTFLOW', 'BOTH'].includes(type)) {
      throw new BadRequestException('Invalid category type');
    }

    try {
      const category = await this.prisma.transactionCategory.create({
        data: {
          name,
          type,
          companyId: dto.companyId,
          tenantId,
        },
      });
      return category;
    } catch (e: any) {
      if (e.code === 'P2002') {
        throw new ConflictException('Category with this name already exists in this concern.');
      }
      throw new BadRequestException('Failed to create category: ' + e.message);
    }
  }

  async getCategorySummary(companyId: string, categoryId: string) {
    const category = await this.prisma.transactionCategory.findUnique({
      where: { id: categoryId },
    });
    if (!category) {
      throw new NotFoundException('Category not found');
    }
    if (category.companyId !== companyId) {
      throw new BadRequestException('Category does not belong to specified company');
    }

    const supersededRows = await this.prisma.moneyMovement.findMany({
      where: { editedFromId: { not: null } },
      select: { editedFromId: true },
    });
    const supersededIds = new Set<string>(supersededRows.map((r) => r.editedFromId).filter((id): id is string => !!id));

    const movements = await this.prisma.moneyMovement.findMany({
      where: {
        categoryId,
        wallet: { companyId },
      },
      orderBy: { createdAt: 'desc' },
      include: {
        wallet: {
          select: {
            id: true,
            name: true,
            company: { select: { name: true, code: true } },
          },
        },
        collector: {
          select: { id: true, name: true, role: true },
        },
        custodian: {
          select: { id: true, name: true, type: true, linkedUserId: true },
        },
        category: {
          select: { id: true, name: true, type: true },
        },
      },
    });

    const activeMovements = movements.filter((m) => !supersededIds.has(m.id));

    let totalInflow = 0;
    let totalOutflow = 0;

    for (const m of activeMovements) {
      const amt = Number(m.amount) || 0;
      const dir = (m.direction || 'in').toLowerCase();
      if (dir === 'in') {
        totalInflow += amt;
      } else {
        totalOutflow += amt;
      }
    }

    const netBalance = totalInflow - totalOutflow;

    return {
      categoryName: category.name,
      categoryType: category.type,
      totalInflow,
      totalOutflow,
      netBalance,
      transactions: movements,
    };
  }
}
