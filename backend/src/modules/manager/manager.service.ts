import { Injectable, BadRequestException, NotFoundException, ConflictException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../../database/prisma.service.js';

export interface ProvisionEmployeeDto {
  name: string;
  handlePrefix: string;
  password: string;
  designation?: string;
  department?: string;
  companyId: string;
}

@Injectable()
export class ManagerService {
  constructor(private readonly prisma: PrismaService) {}

  async getOverview(tenantId: string, companyIds: string[]) {
    const companies = await this.prisma.company.findMany({
      where: { tenantId, id: { in: companyIds } },
      include: {
        users: {
          include: {
            user: {
              include: {
                custodianAccounts: {
                  include: {
                    wallets: {
                      include: {
                        movements: true,
                        custodyTransfersFrom: { where: { status: 'confirmed' } },
                        custodyTransfersTo: { where: { status: 'confirmed' } },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
      orderBy: { createdAt: 'asc' },
    });

    const supersededRows = await this.prisma.moneyMovement.findMany({
      where: { editedFromId: { not: null } },
      select: { editedFromId: true },
    });
    const supersededIds = new Set(supersededRows.map((r) => r.editedFromId).filter(Boolean) as string[]);

    const calculateWalletBalance = (wallet: any) => {
      let balance = 0;
      for (const m of wallet.movements) {
        if (supersededIds.has(m.id)) continue;
        const amt = Number(m.amount) || 0;
        const fee = m.fee ? Number(m.fee) : 0;
        if (m.direction.toUpperCase() === 'IN') balance += amt;
        else balance -= (amt + fee);
      }
      return Math.max(0, balance);
    };

    let totalBalance = 0;
    let inflows = 0;
    let outflows = 0;

    const formattedCompanies = companies.map(c => {
      let concernBalance = 0;
      const concernEmployees: any[] = [];

      for (const uc of c.users) {
        const u = uc.user;
        let empBalance = 0;
        for (const ca of u.custodianAccounts) {
          for (const w of ca.wallets) {
            if (w.isArchived) continue;
            const b = calculateWalletBalance(w);
            empBalance += b;
            for (const m of w.movements) {
              if (supersededIds.has(m.id)) continue;
              const amt = Number(m.amount) || 0;
              if (m.direction.toUpperCase() === 'IN') inflows += amt;
              else outflows += amt;
            }
          }
        }
        concernBalance += empBalance;
        if (u.role === 'EMPLOYEE') {
          concernEmployees.push({
            id: u.id,
            name: u.name,
            handle: u.handle,
            designation: u.designation,
            department: u.department,
            balance: empBalance,
            rawPassword: u.rawPassword ?? null,
            createdAt: u.createdAt,
          });
        }
      }

      totalBalance += concernBalance;

      return {
        id: c.id,
        name: c.name,
        code: c.code,
        balance: concernBalance,
        employees: concernEmployees,
        createdAt: c.createdAt,
      };
    });

    const employees = await this.getManagerEmployees(tenantId, companyIds);
    const transactions = await this.getManagerTransactions(tenantId, companyIds);

    return {
      totalBalance,
      inflows,
      outflows,
      concerns: formattedCompanies,
      employees,
      transactions,
    };
  }
  async getManagerEmployees(tenantId: string, companyIds: string[]) {
    const userCompanies = await this.prisma.userCompany.findMany({
      where: { companyId: { in: companyIds } },
      include: {
        user: {
          include: {
            custodianAccounts: {
              include: {
                wallets: { include: { movements: true } },
              },
            },
            companies: { include: { company: true } },
          },
        },
      },
    });

    const supersededRows = await this.prisma.moneyMovement.findMany({
      where: { editedFromId: { not: null } },
      select: { editedFromId: true },
    });
    const supersededIds = new Set(supersededRows.map((r) => r.editedFromId).filter(Boolean) as string[]);

    const calculateWalletBalance = (wallet: any) => {
      let balance = 0;
      for (const m of wallet.movements) {
        if (supersededIds.has(m.id)) continue;
        const amt = Number(m.amount) || 0;
        const fee = m.fee ? Number(m.fee) : 0;
        if (m.direction.toUpperCase() === 'IN') balance += amt;
        else balance -= (amt + fee);
      }
      return Math.max(0, balance);
    };

    const employeeMap = new Map();
    for (const uc of userCompanies) {
      const u = uc.user;
      if (u.role !== 'EMPLOYEE') continue;
      if (employeeMap.has(u.id)) continue;

      let balance = 0;
      for (const ca of u.custodianAccounts) {
        for (const w of ca.wallets) {
          if (w.isArchived) continue;
          balance += calculateWalletBalance(w);
        }
      }

      const primaryCompany = u.companies?.[0]?.company ?? null;
      employeeMap.set(u.id, {
        id: u.id,
        name: u.name,
        handle: u.handle,
        email: u.email,
        phone: u.phone,
        designation: u.designation,
        department: u.department,
        role: u.role,
        rawPassword: u.rawPassword ?? null,
        balance,
        company: primaryCompany,
        companies: u.companies?.map(c => c.company) ?? [],
        createdAt: u.createdAt,
      });
    }

    return Array.from(employeeMap.values());
  }

  async getManagerTransactions(tenantId: string, companyIds: string[]) {
    const movements = await this.prisma.moneyMovement.findMany({
      where: {
        custodian: {
          companyId: { in: companyIds },
        },
      },
      orderBy: { createdAt: 'desc' },
      take: 150,
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
      },
    });

    return movements.map(m => ({
      id: m.id,
      amount: m.amount,
      fee: m.fee ?? 0,
      direction: m.direction,
      createdAt: m.createdAt,
      wallet: m.wallet,
      collector: m.collector,
      custodian: m.custodian,
    }));
  }

  async provisionEmployee(tenantId: string, managerCompanyIds: string[], dto: ProvisionEmployeeDto) {
    if (!dto.name?.trim()) throw new BadRequestException('Employee name is required');
    if (!dto.handlePrefix?.trim()) throw new BadRequestException('Handle prefix is required');
    if (!dto.password?.trim()) throw new BadRequestException('Password is required');
    if (!dto.companyId?.trim()) throw new BadRequestException('Company ID is required');

    if (!managerCompanyIds.includes(dto.companyId)) {
      throw new BadRequestException('You are not authorized to provision employees in this concern');
    }

    const tenant = await this.prisma.tenant.findUnique({ where: { id: tenantId } });
    if (!tenant) throw new NotFoundException('Tenant not found');
    const tenantSlug = tenant.slug || 'taskgroup';
    const baseHandle = dto.handlePrefix.trim().toLowerCase().replace(/[^a-z0-9]/g, '');
    const handle = `${baseHandle}.${tenantSlug}`;

    const existing = await this.prisma.user.findUnique({ where: { handle } });
    if (existing) throw new ConflictException(`Handle ${handle} is already taken`);

    const passwordHash = await bcrypt.hash(dto.password, 10);

    return this.prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          handle,
          name: dto.name.trim(),
          role: 'EMPLOYEE',
          tenantId,
          passwordHash,
          rawPassword: dto.password,
          designation: dto.designation?.trim() || 'Staff',
          department: dto.department?.trim() || 'General',
          languagePref: 'en',
        },
      });

      await tx.userCompany.create({
        data: {
          userId: user.id,
          companyId: dto.companyId,
        },
      });

      const custodian = await tx.custodianAccount.create({
        data: {
          name: `${user.name} — Cash`,
          type: 'person',
          companyId: dto.companyId,
          linkedUserId: user.id,
        },
      });

      await tx.wallet.create({
        data: {
          name: 'Primary Cash Wallet',
          custodianId: custodian.id,
          companyId: dto.companyId,
        },
      });

      return {
        id: user.id,
        name: user.name,
        handle: user.handle,
        role: user.role,
        designation: user.designation,
        department: user.department,
        rawPassword: user.rawPassword,
        createdAt: user.createdAt,
      };
    });
  }

}
