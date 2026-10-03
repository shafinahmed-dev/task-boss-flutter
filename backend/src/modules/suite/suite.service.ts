import { Injectable, NotFoundException, ConflictException, BadRequestException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../../database/prisma.service.js';

export interface CreateConcernDto { name: string; code: string; }
export interface UpdateConcernDto { name?: string; code?: string; }
export interface ProvisionManagerDto { name: string; handlePrefix: string; password: string; designation: string; companyIds: string[]; }
export interface UpdateManagerDto { name?: string; designation?: string; password?: string; handlePrefix?: string; companyIds?: string[]; }

@Injectable()
export class SuiteService {
  constructor(private readonly prisma: PrismaService) {}

  async getConcerns(tenantId: string) {
    const companies = await this.prisma.company.findMany({
      where: { tenantId },
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

    return companies.map(c => {
      const assignedMembers = c.users.filter(uc => uc.user && uc.user.role !== 'SUITE_ADMIN');
      let totalBalance = 0;
      for (const uc of assignedMembers) {
        const u = uc.user;
        for (const ca of u.custodianAccounts) {
          for (const w of ca.wallets) {
            if (w.isArchived) continue;
            totalBalance += calculateWalletBalance(w);
          }
        }
      }
      return {
        id: c.id,
        name: c.name,
        code: c.code ?? '',
        tenantId: c.tenantId,
        createdAt: c.createdAt,
        totalMembers: assignedMembers.length,
        totalBalance,
      };
    });
  }

  async createConcern(tenantId: string, dto: CreateConcernDto) {
    if (!dto.name?.trim()) throw new BadRequestException('Concern name is required');
    if (!dto.code?.trim()) throw new BadRequestException('Concern code is required');
    const code = dto.code.trim().toUpperCase();
    const existing = await this.prisma.company.findFirst({ where: { tenantId, code } });
    if (existing) throw new ConflictException(`Company with code ${code} already exists`);
    return this.prisma.$transaction(async (tx) => {
      const company = await tx.company.create({ data: { name: dto.name.trim(), code, tenantId } });
      await tx.custodianAccount.create({ data: { name: `${company.name} — Company Root`, type: 'company', companyId: company.id } });
      return { id: company.id, name: company.name, code: company.code, tenantId: company.tenantId, createdAt: company.createdAt };
    });
  }

  async updateConcern(tenantId: string, id: string, dto: UpdateConcernDto) {
    const company = await this.prisma.company.findFirst({ where: { id, tenantId } });
    if (!company) throw new NotFoundException('Company not found');
    
    let code = company.code;
    if (dto.code?.trim()) {
      code = dto.code.trim().toUpperCase();
      const existing = await this.prisma.company.findFirst({ where: { tenantId, code, id: { not: id } } });
      if (existing) throw new ConflictException(`Company with code ${code} already exists`);
    }
    
    return this.prisma.company.update({
      where: { id },
      data: { name: dto.name?.trim() || company.name, code },
    });
  }

  async deleteConcern(tenantId: string, id: string) {
    const company = await this.prisma.company.findFirst({
      where: { id, tenantId },
      include: { custodianAccounts: { include: { wallets: { include: { movements: { take: 1 }, custodyTransfersFrom: { take: 1 }, custodyTransfersTo: { take: 1 } } } } } }
    });
    if (!company) throw new NotFoundException('Company not found');
    
    let hasMovements = false;
    for (const ca of company.custodianAccounts) {
      for (const w of ca.wallets) {
        if (w.movements.length > 0 || w.custodyTransfersFrom.length > 0 || w.custodyTransfersTo.length > 0) hasMovements = true;
      }
    }
    if (hasMovements) throw new BadRequestException('Cannot delete company with active transactions.');
    
    return this.prisma.company.delete({ where: { id } });
  }

  async getManagers(tenantId: string) {
    const managers = await this.prisma.user.findMany({
      where: { tenantId, role: 'MANAGER' },
      include: { companies: { include: { company: { select: { id: true, name: true, code: true } } } } },
      orderBy: { createdAt: 'desc' },
    });
    return managers.map(m => ({
      id: m.id, handle: m.handle, name: m.name, email: m.email, phone: m.phone, designation: m.designation,
      department: m.department, role: m.role, rawPassword: m.rawPassword ?? null, companies: m.companies?.map(uc => uc.company) ?? [], createdAt: m.createdAt,
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
    
    const existing = await this.prisma.user.findUnique({ where: { handle } });
    if (existing) throw new ConflictException(`Handle ${handle} is already taken`);
    
    if (dto.companyIds && dto.companyIds.length > 0) {
      const valid = await this.prisma.company.findMany({ where: { id: { in: dto.companyIds }, tenantId } });
      if (valid.length !== dto.companyIds.length) throw new BadRequestException('Invalid selected companies');
    }
    
    const passwordHash = await bcrypt.hash(dto.password, 10);
    return this.prisma.$transaction(async (tx) => {
      const user = await tx.user.create({
        data: {
          handle, name: dto.name.trim(), role: 'MANAGER', tenantId,
          designation: dto.designation?.trim() || 'Manager', department: 'Management', languagePref: 'bn', passwordHash,
          rawPassword: dto.password,
        },
      });
      if (dto.companyIds && dto.companyIds.length > 0) {
        await tx.userCompany.createMany({
          data: dto.companyIds.map(companyId => ({ userId: user.id, companyId })),
        });
        await tx.custodianAccount.create({ data: { name: `${user.name} — Custodian Account`, type: 'user', linkedUserId: user.id, companyId: dto.companyIds[0] } });
      }
      return { id: user.id, handle: user.handle, name: user.name, role: user.role, designation: user.designation, rawPassword: user.rawPassword, companyIds: dto.companyIds };
    });
  }

  async updateManager(tenantId: string, id: string, dto: UpdateManagerDto) {
    const user = await this.prisma.user.findFirst({ where: { id, tenantId, role: 'MANAGER' } });
    if (!user) throw new NotFoundException('Manager not found');
    
    const data: any = {};
    if (dto.name?.trim()) data.name = dto.name.trim();
    if (dto.designation?.trim()) data.designation = dto.designation.trim();
    if (dto.password?.trim()) {
      data.passwordHash = await bcrypt.hash(dto.password, 10);
      data.rawPassword = dto.password;
    }
    if (dto.handlePrefix?.trim()) {
      const tenant = await this.prisma.tenant.findUnique({ where: { id: tenantId } });
      if (!tenant) throw new NotFoundException('Tenant not found');
      const tenantSlug = tenant.slug || 'taskgroup';
      const handle = `${dto.handlePrefix.trim().toLowerCase()}.${tenantSlug}`;
      const existing = await this.prisma.user.findFirst({ where: { handle, id: { not: id } } });
      if (existing) throw new ConflictException('Handle already in use');
      data.handle = handle;
    }
    
    return this.prisma.$transaction(async (tx) => {
      const updatedUser = await tx.user.update({ where: { id }, data });
      if (dto.companyIds !== undefined) {
        await tx.userCompany.deleteMany({ where: { userId: id } });
        if (dto.companyIds.length > 0) {
          const compIds = [...new Set(dto.companyIds)];
          await tx.userCompany.createMany({ data: compIds.map(cId => ({ userId: id, companyId: cId })) });
        }
      }
      return { id: updatedUser.id, name: updatedUser.name, handle: updatedUser.handle, role: updatedUser.role, rawPassword: updatedUser.rawPassword };
    });
  }

  async deleteManager(tenantId: string, id: string) {
    const user = await this.prisma.user.findFirst({
      where: { id, tenantId, role: 'MANAGER' },
      include: { collectedMovements: { take: 1 } }
    });
    if (!user) throw new NotFoundException('Manager not found');
    if (user.collectedMovements.length > 0) {
      throw new BadRequestException('Cannot delete manager with transaction history.');
    }
    return this.prisma.user.delete({ where: { id } });
  }

  async getLedgerSummary(tenantId: string) {
    const [concernsCount, managersCount, employeesCount] = await Promise.all([
      this.prisma.company.count({ where: { tenantId } }),
      this.prisma.user.count({ where: { tenantId, role: 'MANAGER' } }),
      this.prisma.user.count({ where: { tenantId, role: { notIn: ['SUITE_ADMIN', 'MANAGER'] } } }),
    ]);
    
    const movements = await this.prisma.moneyMovement.findMany({
      where: { custodian: { company: { tenantId } }, editedFromId: null },
      select: { direction: true, amount: true, fee: true },
    });
    let totalCash = 0;
    for (const m of movements) {
      const amt = Number(m.amount) || 0;
      const fee = Number(m.fee) || 0;
      if (m.direction.toUpperCase() === 'IN') totalCash += amt;
      else totalCash -= (amt + fee);
    }
    const transfers = await this.prisma.custodyTransfer.findMany({
      where: { fromCustodian: { company: { tenantId } }, status: 'confirmed' },
      select: { fee: true }
    });
    const transferFees = transfers.reduce((sum, t) => sum + (Number(t.fee) || 0), 0);
    totalCash -= transferFees;
    
    return { totalGroupCash: Math.max(0, totalCash), concernsCount, managersCount, employeesCount };
  }

  async getDashboardAnalytics(tenantId: string, period: string = 'month') {
    let startDate = new Date(0);
    const now = new Date();
    if (period === 'today') {
      startDate = new Date(now);
      startDate.setHours(0, 0, 0, 0);
    } else if (period === 'week') {
      startDate = new Date(now);
      startDate.setDate(startDate.getDate() - 7);
    } else if (period === 'month') {
      startDate = new Date(now);
      startDate.setDate(startDate.getDate() - 30);
    }

    const concerns = await this.getConcerns(tenantId);
    const totalGroupCash = concerns.reduce((sum, c) => sum + (c.totalBalance || 0), 0);

    const supersededRows = await this.prisma.moneyMovement.findMany({
      where: { editedFromId: { not: null } },
      select: { editedFromId: true },
    });
    const supersededIds = new Set(supersededRows.map((r) => r.editedFromId).filter(Boolean) as string[]);

    const movements = await this.prisma.moneyMovement.findMany({
      where: {
        custodian: { company: { tenantId } },
        createdAt: { gte: startDate },
      },
      select: { id: true, direction: true, amount: true, createdAt: true },
    });

    let inflow = 0;
    let outflow = 0;
    for (const m of movements) {
      if (supersededIds.has(m.id)) continue;
      const amt = Number(m.amount) || 0;
      if (m.direction.toUpperCase() === 'IN') {
        inflow += amt;
      } else if (m.direction.toUpperCase() === 'OUT') {
        outflow += amt;
      }
    }

    const managers = await this.prisma.user.findMany({
      where: { tenantId, role: 'MANAGER' },
      include: {
        companies: {
          include: {
            company: { select: { id: true, name: true, code: true } },
          },
        },
        custodianAccounts: {
          include: {
            wallets: {
              include: { movements: true },
            },
          },
        },
      },
    });

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

    const managersLeaderboardUnsorted = managers.map(m => {
      let personalBalance = 0;
      for (const ca of m.custodianAccounts) {
        for (const w of ca.wallets) {
          if (w.isArchived) continue;
          personalBalance += calculateWalletBalance(w);
        }
      }
      const sharePercentage = totalGroupCash > 0 ? (personalBalance / totalGroupCash) * 100 : 0;
      return {
        id: m.id,
        name: m.name,
        handle: m.handle,
        email: m.email,
        phone: m.phone,
        designation: m.designation,
        rawPassword: m.rawPassword ?? null,
        personalBalance,
        sharePercentage,
        companies: m.companies?.map(uc => uc.company) ?? [],
      };
    });

    managersLeaderboardUnsorted.sort((a, b) => {
      if (b.personalBalance !== a.personalBalance) {
        return b.personalBalance - a.personalBalance;
      }
      return a.name.localeCompare(b.name);
    });

    const managersLeaderboard = managersLeaderboardUnsorted.map((m, index) => ({
      ...m,
      rank: index + 1,
    }));

    return {
      totalGroupCash,
      inflow,
      outflow,
      concerns,
      managersLeaderboard,
    };
  }

  async getSuiteEmployees(tenantId: string) {
    const employees = await this.prisma.user.findMany({
      where: { tenantId, role: 'EMPLOYEE' },
      include: {
        companies: { include: { company: true } },
        custodianAccounts: {
          include: {
            wallets: { include: { movements: true } },
          },
        },
      },
      orderBy: { createdAt: 'desc' },
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

    return employees.map(e => {
      let balance = 0;
      for (const ca of e.custodianAccounts) {
        for (const w of ca.wallets) {
          if (w.isArchived) continue;
          balance += calculateWalletBalance(w);
        }
      }
      const primaryCompany = e.companies?.[0]?.company ?? null;
      return {
        id: e.id,
        name: e.name,
        handle: e.handle,
        email: e.email,
        phone: e.phone,
        designation: e.designation,
        department: e.department,
        role: e.role,
        rawPassword: e.rawPassword ?? null,
        balance,
        company: primaryCompany,
        companies: e.companies?.map(uc => uc.company) ?? [],
        createdAt: e.createdAt,
      };
    });
  }

  async updateUserPassword(tenantId: string, userId: string, newPassword: string) {
    if (!newPassword?.trim()) throw new BadRequestException('New password is required');
    const user = await this.prisma.user.findFirst({ where: { id: userId, tenantId } });
    if (!user) throw new NotFoundException('User not found');
    const passwordHash = await bcrypt.hash(newPassword, 10);
    await this.prisma.user.update({
      where: { id: userId },
      data: { passwordHash, rawPassword: newPassword },
    });
    return { success: true, message: 'Password updated successfully' };
  }

  async getConcernBreakdown(tenantId: string, id: string) {
    const company = await this.prisma.company.findFirst({
      where: { id, tenantId },
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
    });

    if (!company) throw new NotFoundException('Company not found');

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

    const assignedMembers = company.users.filter(uc => uc.user && uc.user.role !== 'SUITE_ADMIN');
    let totalBalance = 0;
    const members = [];

    for (const uc of assignedMembers) {
      const u = uc.user;
      let memberBalance = 0;
      for (const ca of u.custodianAccounts) {
        for (const w of ca.wallets) {
          if (w.isArchived) continue;
          memberBalance += calculateWalletBalance(w);
        }
      }
      totalBalance += memberBalance;
      members.push({
        id: u.id,
        name: u.name,
        handle: u.handle,
        role: u.role,
        designation: u.designation,
        balance: memberBalance,
      });
    }

    return {
      concern: {
        id: company.id,
        name: company.name,
        code: company.code,
        totalBalance,
      },
      members,
    };
  }
}
