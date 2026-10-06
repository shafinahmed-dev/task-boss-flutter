const fs = require('fs');

const code = `import { Injectable, NotFoundException, BadRequestException, ConflictException, ForbiddenException } from '@nestjs/common';
import { PrismaService } from '../../database/prisma.service.js';

@Injectable()
export class CategoryService {
  constructor(private prisma: PrismaService) {}

  private async validateAndAuthorizeCompany(userId: string, tenantId: string, userRole: string, companyId: string) {
    // 1. Verify company exists and belongs to the user's tenant
    const company = await this.prisma.company.findFirst({
      where: { id: companyId, tenantId: tenantId },
    });

    if (!company) {
      throw new ForbiddenException('Company not found in this workspace');
    }

    // 2. Suite Admins have universal access across their tenant
    if (userRole === 'SUITE_ADMIN') {
      return company;
    }

    // 3. Check UserCompany join table or primaryCompanyId
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, role: true, primaryCompanyId: true },
    });

    const hasUserCompanyLink = await this.prisma.userCompany.findFirst({
      where: { userId: userId, companyId: companyId },
    });

    const isAssigned = hasUserCompanyLink || user?.primaryCompanyId === companyId || userRole === 'MANAGER';

    if (!isAssigned) {
      throw new ForbiddenException(\`User is not authorized for company \${companyId}\`);
    }

    // 4. Auto-heal: Ensure UserCompany record exists so future relational queries succeed
    if (!hasUserCompanyLink) {
      try {
        await this.prisma.userCompany.create({
          data: {
            userId: userId,
            companyId: company.id,
            role: userRole,
          },
        });
      } catch (_) {
        // Ignore if concurrent create happened
      }
    }

    return company;
  }

  async getCategories(reqUser: any, companyId?: string, type?: string) {
    let targetCompanyId = companyId;

    if (!targetCompanyId || targetCompanyId.trim() === '' || targetCompanyId === 'null') {
      const userCompany = await this.prisma.userCompany.findFirst({
        where: { userId: reqUser.id },
        select: { companyId: true },
      });
      targetCompanyId = userCompany?.companyId;

      if (!targetCompanyId) {
        const firstCompany = await this.prisma.company.findFirst({
          where: { tenantId: reqUser.tenantId },
          orderBy: { createdAt: 'asc' },
          select: { id: true },
        });
        targetCompanyId = firstCompany?.id;
      }
    }

    if (!targetCompanyId) {
      throw new BadRequestException('No concern found for this workspace');
    }

    const company = await this.prisma.company.findFirst({
      where: { id: targetCompanyId, tenantId: reqUser.tenantId },
    });

    if (!company) {
      throw new ForbiddenException('Invalid or unauthorized companyId');
    }

    const where: any = { companyId: targetCompanyId };
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

  async createCategory(reqUser: any, dto: { name: string; type?: string; companyId: string }) {
    let targetCompanyId: string | undefined = dto.companyId;

    if (!targetCompanyId || targetCompanyId.trim() === '' || targetCompanyId === 'null') {
      const userCompany = await this.prisma.userCompany.findFirst({
        where: { userId: reqUser.id },
        select: { companyId: true },
      });
      targetCompanyId = userCompany?.companyId;

      if (!targetCompanyId) {
        const firstCompany = await this.prisma.company.findFirst({
          where: { tenantId: reqUser.tenantId },
          orderBy: { createdAt: 'asc' },
          select: { id: true },
        });
        targetCompanyId = firstCompany?.id || undefined;
      }
    }

    if (!targetCompanyId) {
      throw new BadRequestException('No concern found for this workspace');
    }

    await this.validateAndAuthorizeCompany(reqUser.id, reqUser.tenantId, reqUser.role, targetCompanyId);

    const name = dto.name?.trim();
    if (!name) {
      throw new BadRequestException('Category name is required');
    }
    const type = (dto.type || 'BOTH').toUpperCase();
    if (!['INFLOW', 'OUTFLOW', 'BOTH'].includes(type)) {
      throw new BadRequestException('Invalid category type');
    }

    try {
      const category = await this.prisma.transactionCategory.upsert({
        where: {
          companyId_name: {
            companyId: targetCompanyId,
            name: name,
          },
        },
        update: {
          type: type,
        },
        create: {
          name: name,
          type: type,
          companyId: targetCompanyId,
          tenantId: reqUser.tenantId,
          createdById: reqUser.id,
        },
      });
      return { success: true, category };
    } catch (e: any) {
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
          select: { id: true, name: true, company: { select: { name: true, code: true } } },
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

  async updateCategory(reqUser: any, id: string, dto: { name?: string; type?: string }) {
    const category = await this.prisma.transactionCategory.findUnique({
      where: { id },
    });
    if (!category) {
      throw new NotFoundException('Category not found');
    }
    if (category.tenantId !== reqUser.tenantId || !['MANAGER', 'SUITE_ADMIN'].includes(reqUser.role)) {
      throw new ForbiddenException('Unauthorized');
    }

    const data: any = {};
    if (dto.name !== undefined) {
      const name = dto.name.trim();
      if (!name) throw new BadRequestException('Category name cannot be empty');
      data.name = name;
    }
    if (dto.type !== undefined) {
      const type = dto.type.toUpperCase();
      if (!['INFLOW', 'OUTFLOW', 'BOTH'].includes(type)) {
        throw new BadRequestException('Invalid category type');
      }
      data.type = type;
    }

    try {
      const updated = await this.prisma.transactionCategory.update({
        where: { id },
        data,
      });
      return { success: true, category: updated };
    } catch (e: any) {
      if (e.code === 'P2002'
