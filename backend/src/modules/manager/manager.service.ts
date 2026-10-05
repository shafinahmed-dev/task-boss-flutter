import { Injectable, BadRequestException, NotFoundException, ConflictException, ForbiddenException } from '@nestjs/common';
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

  private calculateWalletBalance(wallet: any, supersededIds: Set<string>): number {
    let balance = 0;
    for (const m of wallet.movements) {
      if (supersededIds.has(m.id)) continue;
      const amt = Number(m.amount) || 0;
      const fee = m.fee ? Number(m.fee) : 0;
      if (m.direction?.toUpperCase() === 'IN') balance += amt;
      else balance -= (amt + fee);
    }
    return Math.max(0, balance);
  }

  async getOverview(tenantId: string, authorizedCompanyIds: string[], userId: string, requestedCompanyId?: string, period: 'today' | 'week' | 'month' | 'all' = 'month') {
    let managerPersonalBalance = 0;
    const managerCustodianAccounts = await this.prisma.custodianAccount.findMany({
      where: { linkedUserId: userId, isArchived: false },
      include: { wallets: { include: { movements: true } } },
    });
    const supersededRowsForPersonal = await this.prisma.moneyMovement.findMany({
      where: { editedFromId: { not: null } },
      select: { editedFromId: true },
    });
    const supersededIdsSet = new Set<string>(supersededRowsForPersonal.map((r) => r.editedFromId).filter((id): id is string => !!id));

    for (const ca of managerCustodianAccounts) {
      for (const w of ca.wallets) {
        if (w.isArchived) continue;
        managerPersonalBalance += this.calculateWalletBalance(w, supersededIdsSet);
      }
    }

    if (!authorizedCompanyIds || authorizedCompanyIds.length === 0) {
      return { company: null, assignedConcerns: [], velocity: { inflow: 0, outflow: 0 }, recentTransactions: [], topEmployees: [], managerPersonalBalance };
    }

    let targetCompanyId = requestedCompanyId;
    if (!targetCompanyId) {
      targetCompanyId = authorizedCompanyIds[0];
    }
    if (!authorizedCompanyIds.includes(targetCompanyId)) {
      throw new ForbiddenException('Not authorized for this concern');
    }

    const assignedCompanies = await this.prisma.company.findMany({
      where: { tenantId, id: { in: authorizedCompanyIds } },
      include: {
        users: {
          include: {
            user: {
              include: {
                custodianAccounts: {
                  include: {
                    wallets: {
                      include: { movements: true },
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
    const supersededIds = new Set<string>(supersededRows.map((r) => r.editedFromId).filter((id): id is string => !!id));

    const assignedConcerns = assignedCompanies.map(c => {
      let concernBalance = 0;
      for (const uc of c.users) {
        for (const ca of uc.user.custodianAccounts) {
          for (const w of ca.wallets) {
            if (w.isArchived) continue;
            concernBalance += this.calculateWalletBalance(w, supersededIds);
          }
        }
      }
      return {
        id: c.id,
        name: c.name,
        code: c.code,
        totalBalance: concernBalance,
      };
    });

    const targetComp = assignedCompanies.find(c => c.id === targetCompanyId) || assignedCompanies[0];
    if (!targetComp) {
      return { company: null, assignedConcerns, velocity: { inflow: 0, outflow: 0 }, recentTransactions: [], topEmployees: [], managerPersonalBalance };
    }

    let targetCompanyBalance = 0;
    const employeeBalances: Array<{ user: any; balance: number }> = [];

    for (const uc of targetComp.users) {
      const u = uc.user;
      let userBalance = 0;
      for (const ca of u.custodianAccounts) {
        for (const w of ca.wallets) {
          if (w.isArchived) continue;
          userBalance += this.calculateWalletBalance(w, supersededIds);
        }
      }
      targetCompanyBalance += userBalance;
      if (u.role === 'EMPLOYEE') {
        employeeBalances.push({ user: u, balance: userBalance });
      }
    }

    employeeBalances.sort((a, b) => b.balance - a.balance);
    const topEmployees = employeeBalances.slice(0, 3).map(item => ({
      id: item.user.id,
      name: item.user.name,
      handle: item.user.handle,
      designation: item.user.designation,
      department: item.user.department,
      balance: item.balance,
      rawPassword: item.user.rawPassword ?? null,
    }));

    const now = new Date();
    let startDate = new Date(0);
    if (period === 'today') {
      startDate = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    } else if (period === 'week') {
      startDate = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    } else if (period === 'month') {
      startDate = new Date(now.getFullYear(), now.getMonth(), 1);
    }

    const targetWalletIds: string[] = [];
    for (const uc of targetComp.users) {
      for (const ca of uc.user.custodianAccounts) {
        for (const w of ca.wallets) {
          if (!w.isArchived) targetWalletIds.push(w.id);
        }
      }
    }

    let inflow = 0;
    let outflow = 0;
    let recentMovements: any[] = [];

    if (targetWalletIds.length > 0) {
      const movements = await this.prisma.moneyMovement.findMany({
        where: {
          walletId: { in: targetWalletIds },
          createdAt: { gte: startDate },
        },
        orderBy: { createdAt: 'desc' },
        include: {
          wallet: { select: { name: true } },
          collector: { select: { id: true, name: true } },
          custodian: { select: { id: true, name: true } },
        },
      });

      for (const m of movements) {
        if (supersededIds.has(m.id)) continue;
        const amt = Number(m.amount) || 0;
        const dir = m.direction?.toUpperCase() || 'IN';
        if (dir === 'IN') {
          inflow += amt;
        } else {
          outflow += amt;
        }
      }

      recentMovements = movements.filter(m => !supersededIds.has(m.id)).slice(0, 3).map(m => ({
        id: m.id,
        amount: m.amount,
        type: m.direction,
        direction: m.direction,
        description: m.notes || 'Transaction',
        createdAt: m.createdAt,
        actorName: m.collector?.name || m.custodian?.name || 'Staff',
        wallet: m.wallet,
        collector: m.collector,
        custodian: m.custodian,
      }));
    }

    return {
      company: {
        id: targetComp.id,
        name: targetComp.name,
        code: targetComp.code,
        totalBalance: targetCompanyBalance,
      },
      assignedConcerns,
      velocity: {
        inflow,
        outflow,
      },
      recentTransactions: recentMovements,
      topEmployees,
      managerPersonalBalance,
    };
  }

  async getEmployees(companyId: string) {
    const userCompanies = await this.prisma.userCompany.findMany({
      where: { companyId },
      include: {
        user: {
          include: {
            custodianAccounts: {
              include: {
                wallets: { include: { movements: true } },
              },
            },
          },
        },
      },
    });

    const supersededRows = await this.prisma.moneyMovement.findMany({
      where: { editedFromId: { not: null } },
      select: { editedFromId: true },
    });
    const supersededIds = new Set<string>(supersededRows.map((r) => r.editedFromId).filter((id): id is string => !!id));

    const employees: any[] = [];
    for (const uc of userCompanies) {
      const u = uc.user;
      if (u.role !== 'EMPLOYEE') continue;
      let balance = 0;
      for (const ca of u.custodianAccounts) {
        for (const w of ca.wallets) {
          if (w.isArchived) continue;
          for (const m of w.movements) {
            if (supersededIds.has(m.id)) continue;
            const amt = Number(m.amount) || 0;
            const fee = m.fee ? Number(m.fee) : 0;
            if (m.direction?.toUpperCase() === 'IN') balance += amt;
            else balance -= (amt + fee);
          }
        }
      }

      employees.push({
        id: u.id,
        name: u.name,
        handle: u.handle,
        rawPassword: u.rawPassword ?? null,
        designation: u.designation,
        department: u.department,
        balance: Math.max(0, balance),
        companyId,
      });
    }

    return employees;
  }

  async getManagerTransactions(tenantId: string, companyIds: string[]) {
    const movements = await this.prisma.moneyMovement.findMany({
      where: {
        wallet: {
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
      note: m.notes,
    }));
  }

  async provisionEmployee(tenantId: string, managerCompanyIds: string[], dto: ProvisionEmployeeDto) {
    if (!dto.name?.trim()) throw new BadRequestException('Employee name is required');
    if (!dto.handlePrefix?.trim()) throw new BadRequestException('Handle prefix is required');
    if (!dto.password?.trim()) throw new BadRequestException('Password is required');

    let companyId = dto.companyId;
    if (!companyId || companyId === '') {
      if (managerCompanyIds.length > 0) {
        companyId = managerCompanyIds[0];
      } else {
        throw new BadRequestException('Company ID is required');
      }
    }

    if (!managerCompanyIds.includes(companyId)) {
      throw new BadRequestException('You are not authorized to provision employees in this concern');
    }

    const company = await this.prisma.company.findUnique({ where: { id: companyId } });
    if (!company) throw new NotFoundException('Company not found');

    const tenant = await this.prisma.tenant.findUnique({
      where: { id: tenantId },
      select: { id: true, slug: true, name: true },
    });
    const tenantSlug = tenant?.slug?.toLowerCase() || 'taskgroup';

    // Safe migration: update any employee handles ending with incorrect company codes in this tenant
    const employeesToMigrate = await this.prisma.user.findMany({
      where: { tenantId, role: 'EMPLOYEE', NOT: { handle: { endsWith: `.${tenantSlug}` } } }
    });
    for (const emp of employeesToMigrate) {
      const parts = emp.handle.split('.');
      const base = parts[0].replace('@', '');
      const newHandle = `${base}.${tenantSlug}`;
      const exists = await this.prisma.user.findUnique({ where: { handle: newHandle } });
      if (!exists) {
        await this.prisma.user.update({
          where: { id: emp.id },
          data: { handle: newHandle }
        });
      }
    }

    const baseHandle = dto.handlePrefix.trim().toLowerCase().replace(/[^a-z0-9]/g, '');
    const handle = `${baseHandle}.${tenantSlug}`;

    const existing = await this.prisma.user.findUnique({ where: { handle } });
    if (existing) throw new ConflictException('Username already taken in this suite');

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
          companyId,
        },
      });

      const custodian = await tx.custodianAccount.create({
        data: {
          name: user.name + ' — Cash',
          type: 'person',
          companyId,
          linkedUserId: user.id,
        },
      });

      await tx.wallet.create({
        data: {
          name: 'Primary Cash Wallet',
          custodianId: custodian.id,
          companyId,
          type: 'CASH',
        },
      });

      return {
        success: true,
        user: {
          id: user.id,
          name: user.name,
          handle: user.handle,
          role: user.role,
        },
      };
    });
  }

  async updateEmployee(id: string, tenantId: string, managerCompanyIds: string[], dto: any) {
    const user = await this.prisma.user.findUnique({
      where: { id },
      include: { companies: true },
    });
    if (!user) throw new NotFoundException('Employee not found');
    if (user.role !== 'EMPLOYEE') throw new ForbiddenException('Cannot update non-employee');
    if (user.tenantId !== tenantId) throw new ForbiddenException('Unauthorized');

    const userCompanyIds = user.companies.map(c => c.companyId);
    const hasAccess = userCompanyIds.some(cId => managerCompanyIds.includes(cId));
    if (!hasAccess) {
      throw new ForbiddenException('Not authorized to update this employee');
    }

    const updateData: Record<string, any> = {};
    if (dto.name) updateData['name'] = dto.name.trim();
    if (dto.designation !== undefined) updateData['designation'] = dto.designation;
    if (dto.department !== undefined) updateData['department'] = dto.department;
    if (dto.password && dto.password.trim() !== '') {
      updateData['rawPassword'] = dto.password;
      updateData['passwordHash'] = await bcrypt.hash(dto.password, 10);
    }

    // Handle Prefix
    if (dto.handlePrefix && dto.handlePrefix.trim() !== '') {
        const tenant = await this.prisma.tenant.findUnique({
            where: { id: tenantId },
            select: { slug: true },
        });
        const tenantSlug = tenant?.slug?.toLowerCase() || 'taskgroup';
        const cleanPrefix = dto.handlePrefix.trim().toLowerCase().replace(/[^a-z0-9]/g, '');
        const handle = `${cleanPrefix}.${tenantSlug}`;
        
        const existing = await this.prisma.user.findFirst({
            where: { handle, id: { not: id } }
        });
        if (existing) {
            throw new BadRequestException(`Username @${cleanPrefix}.${tenantSlug} is already in use`);
        }
        updateData['handle'] = handle;
    }

    return this.prisma.$transaction(async (tx) => {
        const updated = await tx.user.update({
            where: { id },
            data: updateData,
        });

        // Company Update
        if (dto.companyId && dto.companyId !== userCompanyIds[0]) {
            if (!managerCompanyIds.includes(dto.companyId)) {
                throw new ForbiddenException('Not authorized for target company');
            }
            await tx.userCompany.deleteMany({ where: { userId: id } });
            await tx.userCompany.create({
                data: {
                    userId: id,
                    companyId: dto.companyId,
                }
            });
        }

        return {
            success: true,
            user: updated,
        };
    });
  }
}
