import { Injectable, NotFoundException, ConflictException, BadRequestException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../../database/prisma.service.js';

export interface CreateConcernDto {
  name: string;
  code: string;
}

export interface ProvisionManagerDto {
  name: string;
  handlePrefix: string;
  password: string;
  designation: string;
  companyIds: string[];
}

@Injectable()
export class SuiteService {
  constructor(private readonly prisma: PrismaService) {}

  async getConcerns(tenantId: string) {
    const companies = await this.prisma.company.findMany({
      where: { tenantId },
      include: {
        custodianAccounts: {
          select: {
            id: true,
            _count: { select: { wallets: { where: { isArchived: false } } } },
          },
        },
      },
      orderBy: { createdAt: 'asc' },
    });

    return companies.map((c) => {
      const totalWallets = c.custodianAccounts.reduce((sum, ca) => sum + (ca._count?.wallets ?? 0), 0);
      return {
        id: c.id,
        name: c.name,
        code: c.code ?? '',
        tenantId: c.tenantId,
        createdAt: c.createdAt,
        totalCustodians: c.custodianAccounts.length,
        totalWallets,
      };
    });
  }

  async createConcern(tenantId: string, dto: CreateConcernDto) {
    if (!dto.name?.trim()) throw new BadRequestException('Concern name is required');
    if (!dto.code?.trim()) throw new BadRequestException('Concern code (short code) is required');

    const code = dto.code.trim().toUpperCase();
    const existing = await this.prisma.company.findFirst({ where: { tenantId, code } });
    if (existing) {
      throw new ConflictException(`Company with code ${code} already exists in this tenant`);
    }

    return this.prisma.$transaction(async (tx) => {
      const company = await tx.company.create({
        data: { name: dto.name.trim(), code, tenantId },
      });

      await tx.custodianAccount.create({
        data: { name: `${company.name} — Company Root`, type: 'company', companyId: company.id },
      });

      return {
        id: company.id,
        name: company.name,
        code: company.code,
        tenantId: company.tenantId,
        createdAt: company.createdAt,
      };
    });
  }

  async getManagers(tenantId: string) {
    const managers = await this.prisma.user.findMany({
      where: {
        tenantId,
        role: 'MANAGER',
      },
      include: {
        companies: {
          include: {
            company: {
              select: { id: true, name: true, code: true },
            },
          },
        },
      },
      orderBy: { createdAt: 'desc' },
    });

    return managers.map((m) => ({
      id: m.id,
      handle: m.handle,
      name: m.name,
      email: m.email,
      phone: m.phone,
      designation: m.designation,
      department: m.department,
      role: m.role,
      companies: m.companies.map((uc) => uc.company),
      createdAt: m.createdAt,
    }));
  }

  async provisionManager(tenantId: string, dto: ProvisionManagerDto) {
    if (!dto.name?.trim()) throw new BadRequestException('Manager name is required');
    if (!dto.handlePrefix?.trim()) throw new BadRequestException('Handle prefix is required');
    if (!dto.password?.trim()) throw new BadRequestException('Password is required');

    const tenant = await this.prisma.tenant.findUnique({ where: { id: tenantId } });
    if (!tenant) throw new NotFoundException('Tenant not found');

    const tenantSlug = tenant.slug || 'taskgroup';
    const baseHandle = dto.handlePrefix.trim().toLowerCase().replace(/[^a-z0-9]/g, '');
    let handle = `${baseHandle}.${tenantSlug}`;

    const existingUser = await this.prisma.user.findUnique({ where: { handle } });
    if (existingUser) {
      handle = `${baseHandle}${Date.now() % 10000}.${tenantSlug}`;
    }

    if (dto.companyIds && dto.companyIds.length > 0) {
      const validCompanies = await this.prisma.company.findMany({
        where: { id: { in: dto.companyIds }, tenantId },
      });
      if (validCompanies.length !== dto.companyIds.length) {
        throw new BadRequestException('One or more selected companies are invalid or do not belong to this tenant');
      }
    }

    const passwordHash = await bcrypt.hash(dto.password, 10);

    return this.prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          handle,
          name: dto.name.trim(),
          role: 'MANAGER',
          tenantId,
          designation: dto.designation?.trim() || 'Manager',
          department: 'Executive',
          languagePref: 'bn',
          passwordHash,
        },
      });

      if (dto.companyIds && dto.companyIds.length > 0) {
        await tx.userCompany.createMany({
          data: dto.companyIds.map((companyId) => ({
            userId: user.id,
            companyId,
          })),
        });

        // Also provision a custodian account for the manager in their primary assigned company
        await tx.custodianAccount.create({
          data: {
            name: `${user.name} — Custodian Account`,
            type: 'user',
            userId: user.id,
            companyId: dto.companyIds[0],
          },
        });
      }

      return {
        id: user.id,
        handle: user.handle,
        name: user.name,
        role: user.role,
        designation: user.designation,
        companyIds: dto.companyIds,
      };
    });
  }

  async getLedgerSummary(tenantId: string) {
    const [concernsCount, managersCount, employeesCount, companies] = await Promise.all([
      this.prisma.company.count({ where: { tenantId } }),
      this.prisma.user.count({ where: { tenantId, role: 'MANAGER' } }),
      this.prisma.user.count({ where: { tenantId, role: { notIn: ['SUITE_ADMIN', 'MANAGER'] } } }),
      this.prisma.company.findMany({
        where: { tenantId },
        include: {
          custodianAccounts: {
            include: {
              wallets: {
                where: { isArchived: false },
              },
            },
          },
        },
      }),
    ]);

    let totalGroupCash = 0;

    // Let's compute total cash across wallets using money movements
    const movements = await this.prisma.moneyMovement.findMany({
      where: {
        custodian: { company: { tenantId } },
        editedFromId: null,
      },
      select: {
        direction: true,
        amount: true,
        fee: true,
      },
    });

    let totalIn = 0;
    let totalOut = 0;
    for (const m of movements) {
      const amt = Number(m.amount) || 0;
      const fee = Number(m.fee) || 0;
      if (m.direction === 'IN' || m.direction === 'in') {
        totalIn += amt;
      } else {
        totalOut += (amt + fee);
      }
    }
    
    // In a closed system tenant transfers cancel, but if transfers leak out, they affect net.
    // For simplicity, net cash = total IN movements - total OUT movements. 
    // CustodyTransfers between two internal wallets are net 0 (totalIn += amt, totalOut += amt) assuming no fees leaked outside.
    // If there's transfer fee, it drops the total cash. We query transfer fees.
    const transfers = await this.prisma.custodyTransfer.findMany({
      where: {
        fromCustodian: { company: { tenantId } },
        status: 'confirmed',
      },
      select: { fee: true }
    });
    const transferFees = transfers.reduce((sum, t) => sum + (Number(t.fee) || 0), 0);

    totalGroupCash = totalIn - totalOut - transferFees;

    return {
      totalGroupCash: Math.max(0, totalGroupCash),
      concernsCount,
      managersCount,
      employeesCount,
    };
  }
}
