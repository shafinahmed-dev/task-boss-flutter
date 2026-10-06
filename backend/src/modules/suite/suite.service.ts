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
      include: { 
        companies: { include: { company: { select: { id: true, name: true, code: true } } } },
        custodianAccounts: {
          include: { wallets: { include: { movements: true } } }
        }
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

    return managers.map(m => {
      let balance = 0;
      for (const ca of m.custodianAccounts) {
        for (const w of ca.wallets) {
          if (w.isArchived) continue;
          balance += calculateWalletBalance(w);
        }
      }
      return {
        id: m.id, handle: m.handle, name: m.name, email: m.email, phone: m.phone, designation: m.designation,
        department: m.department, role: m.role, rawPassword: m.rawPassword ?? null, companies: (m as any).companies?.map((uc: any) => uc.company) ?? [], createdAt: m.createdAt,
        balance,
      };
    });
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
    // 1. Fetch all managers under this tenant in one query
    const managers = await this.prisma.user.findMany({
      where: {
        tenantId,
        role: 'MANAGER',
      },
      select: {
        id: true,
        name: true,
        companies: {
          select: { companyId: true },
        },
      },
    });

    // Map companyId -> Manager Name
    const companyManagerMap = new Map<string, string>();
    for (const mgr of managers) {
      if (mgr.companies) {
        for (const uc of mgr.companies) {
          if (!companyManagerMap.has(uc.companyId)) {
            companyManagerMap.set(uc.companyId, mgr.name);
          }
        }
      }
    }

    // 2. Fetch all employees with companies and wallets included
    const employees = await this.prisma.user.findMany({
      where: {
        tenantId,
        role: 'EMPLOYEE',
      },
      include: {
        companies: {
          include: {
            company: {
              select: { id: true, name: true, code: true },
            },
          },
        },
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

    // 3. Synchronously map employees with zero risk of unhandled Promise rejections
    const serializedEmployees = employees.map((emp) => {
      const firstCompanyRel = emp.companies?.[0];
      const companyId = firstCompanyRel?.companyId;
      const companyCode = firstCompanyRel?.company?.code || 'TDC';
      const companyName = firstCompanyRel?.company?.name || 'Task Design & Consultancy';

      // Lookup manager from map or fallback to first manager in tenant
      const managerName = companyId
        ? companyManagerMap.get(companyId) || (managers[0]?.name ?? 'Shovon Ahmed')
        : (managers[0]?.name ?? 'Shovon Ahmed');

      let balance = 0;
      if (emp.custodianAccounts) {
        for (const ca of emp.custodianAccounts) {
          if (ca.wallets) {
            for (const w of ca.wallets) {
              if (w.isArchived) continue;
              balance += calculateWalletBalance(w);
            }
          }
        }
      }

      return {
        id: emp.id,
        name: emp.name,
        handle: emp.handle,
        designation: emp.designation || 'Staff',
        department: emp.department || '',
        companyId: companyId || '',
        companyCode: companyCode,
        companyName: companyName,
        company: firstCompanyRel?.company || null,
        managerName: managerName,
        balance: Number(balance),
        rawPassword: emp.rawPassword || '••••••••',
      };
    });

    return { success: true, employees: serializedEmployees };
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


  async getSuiteTransactions(
    tenantId: string,
    companyId?: string,
    range?: string,
    search?: string,
  ) {
    const companies = await this.prisma.company.findMany({
      where: { tenantId },
      select: { id: true, name: true, code: true },
    });
    const companyMap = new Map(companies.map((c) => [c.id, c]));
    const tenantCompanyIds = companies.map((c) => c.id);

    // Re-align categories created by TDC managers to TDC if needed
    const tdcCompany = companies.find((c) =>
      c.name.toLowerCase().includes('task design') || c.code === 'TDC'
    );
    if (tdcCompany) {
      try {
        await this.prisma.transactionCategory.updateMany({
          where: {
            companyId: { in: tenantCompanyIds },
            name: { in: ['Office Supplies', 'Barakah Condominium', 'General'] },
          },
          data: { companyId: tdcCompany.id },
        });
      } catch (_) {}
    }

    let startDate;
    const now = new Date();
    if (range === 'today') startDate = new Date(now.setHours(0, 0, 0, 0));
    else if (range === 'this_week') {
      const d = new Date(now.setHours(0, 0, 0, 0));
      d.setDate(d.getDate() - d.getDay());
      startDate = d;
    } else if (range === 'this_month') {
      startDate = new Date(now.getFullYear(), now.getMonth(), 1);
    }

    const movementsWhere: any = {
      wallet: { companyId: { in: tenantCompanyIds } },
    };
    if (startDate) movementsWhere.createdAt = { gte: startDate };

    const movements = await this.prisma.moneyMovement.findMany({
      where: movementsWhere,
      orderBy: { createdAt: 'desc' },
      include: {
        category: {
          select: { id: true, name: true, companyId: true },
        },
        collector: {
          select: {
            id: true,
            name: true,
            role: true,
            companies: {
              select: { companyId: true },
            },
          },
        },
        wallet: {
          select: { id: true, name: true, companyId: true },
        },
      },
    });

    let transactions = movements.map((tx) => {
      const authorCompanyId = tx.collector?.companies?.[0]?.companyId;
      const categoryCompanyId = tx.category?.companyId;
      const walletCompanyId = tx.wallet?.companyId;

      const resolvedCompanyId = authorCompanyId || categoryCompanyId || walletCompanyId;
      const comp = resolvedCompanyId ? companyMap.get(resolvedCompanyId) : null;

      const companyCode = comp?.code
        ? comp.code
        : comp?.name
        ? comp.name.split(' ').map((w: string) => w[0]).join('').toUpperCase()
        : 'TDC';

      const companyName = comp?.name || 'Task Design & Consultancy';
      const segmentName = tx.category?.name || 'General';

      const isOut =
        tx.direction === 'out' ||
        tx.direction === 'OUT' ||
        (tx as any).type === 'CASH_OUT' ||
        (tx as any).type === 'EXPENSE' ||
        (tx as any).movementType === 'Cash Out' ||
        (tx as any).movementType === 'Expense';

      return {
        id: tx.id,
        companyId: resolvedCompanyId || '',
        companyName: companyName,
        companyCode: companyCode,
        segmentName: segmentName,
        amount: Number(tx.amount || 0),
        fee: Number(tx.fee || 0),
        direction: isOut ? 'out' : 'in',
        type: isOut ? 'Cash Out' : 'Cash In',
        note: tx.notes || (tx as any).note || (tx as any).movementType || '',
        actorName: tx.collector?.name || 'System',
        actorRole: tx.collector?.role || 'STAFF',
        walletName: tx.wallet?.name || 'Cash in Hand',
        createdAt: tx.createdAt.toISOString(),
      };
    });

    if (companyId && companyId !== 'null' && companyId !== '') {
      transactions = transactions.filter((t) => t.companyId === companyId);
    }

    if (search && search.trim() !== '') {
      const q = search.trim().toLowerCase();
      transactions = transactions.filter(
        (f) =>
          f.companyCode.toLowerCase().includes(q) ||
          f.companyName.toLowerCase().includes(q) ||
          f.segmentName.toLowerCase().includes(q) ||
          f.actorName.toLowerCase().includes(q) ||
          f.note.toLowerCase().includes(q) ||
          String(f.amount).toLowerCase().includes(q)
      );
    }

    return { success: true, transactions };
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

  async getSuiteOverview(tenantId: string, range?: string, companyId?: string) {
    const companies = await this.prisma.company.findMany({ 
      where: { tenantId }, 
      include: { users: { include: { user: { include: { custodianAccounts: true } } } } } 
    });
    
    let targetIds = companies.map(c => c.id);
    if (companyId && companyId !== 'null' && companyId !== '') {
       targetIds = targetIds.filter(id => id === companyId);
    }
    const targetCompanies = companies.filter(c => targetIds.includes(c.id));
    
    let startDate;
    const now = new Date();
    if (range === 'today') startDate = new Date(now.setHours(0,0,0,0));
    else if (range === 'this_week') { const d = new Date(now.setHours(0,0,0,0)); d.setDate(d.getDate() - d.getDay()); startDate = d; }
    else if (range === 'this_month') startDate = new Date(now.getFullYear(), now.getMonth(), 1);
    
    const movementsWhere = { wallet: { companyId: { in: targetIds } } } as any;
    if (startDate) movementsWhere.createdAt = { gte: startDate };
    const movements = await (this.prisma.moneyMovement as any).findMany({
       where: movementsWhere,
       include: { wallet: true }
    });
    
    const supersededRows = await this.prisma.moneyMovement.findMany({ where: { editedFromId: { not: null } }, select: { editedFromId: true } });
    const supersededIds = new Set(supersededRows.map((r) => r.editedFromId).filter(Boolean));

    let consolidatedBalance = 0;
    let inflow = 0; let outflow = 0; 
    const companyStats = {} as any;
    for (const comp of targetCompanies) companyStats[comp.id] = { inflow: 0, outflow: 0, bal: 0 };
    
    for (const m of movements) {
      if (supersededIds.has(m.id)) continue;
      const isOut = m.direction === 'out' || m.direction === 'OUT' || m.type === 'CASH_OUT' || m.type === 'EXPENSE' || m.movementType === 'Cash Out' || m.movementType === 'Expense';
      const amt = Number(m.amount || 0); const mappedDir = isOut ? 'out' : 'in';
      if (mappedDir === 'in') inflow += amt; else outflow += amt;
      const cId = m.wallet?.companyId;
      if (cId && companyStats[cId]) { if (mappedDir === 'in') companyStats[cId].inflow += amt; else companyStats[cId].outflow += amt; }
    }
    
    const allMovements = await (this.prisma.moneyMovement as any).findMany({
       where: { wallet: { companyId: { in: targetIds } } },
       include: { wallet: true, custodian: { include: { user: true } } }
    });
    
    const wBals = new Map();
    for (const m of allMovements) {
       if (supersededIds.has(m.id)) continue;
       const isOut = m.direction === 'out' || m.direction === 'OUT' || m.type === 'CASH_OUT' || m.type === 'EXPENSE' || m.movementType === 'Cash Out' || m.movementType === 'Expense';
       const amt = Number(m.amount || 0); const fee = Number(m.fee || 0);
       const dir = isOut ? -1 : 1;
       const wId = m.walletId;
       if (!wBals.has(wId)) wBals.set(wId, { cId: m.wallet.companyId, custName: m.custodian?.user?.name || m.custodian?.name || 'Unknown', bal: 0 });
       const w = wBals.get(wId);
       w.bal += (dir === 1 ? amt : -(amt + fee));
    }
    
    for (const w of wBals.values()) {
       if (w.bal > 0) {
          consolidatedBalance += w.bal;
          if (companyStats[w.cId]) companyStats[w.cId].bal += w.bal;
       }
    }
    
    const companyMap = new Map();
    companies.forEach(c => companyMap.set(c.id, c));
    
    const custodianExposure = [];
    for (const w of wBals.values()) {
       if (w.bal > 0) {
          const c = companyMap.get(w.cId);
          custodianExposure.push({
             custodianName: w.custName,
             concernCode: c?.code || 'Gen',
             concernName: c?.name || 'General',
             balance: w.bal
          });
       }
    }
    custodianExposure.sort((a,b) => b.balance - a.balance);
    const topExposure = custodianExposure.slice(0, 20);
    
    const netVelocity = inflow - outflow;
    const perCompanyPerformance = targetCompanies.map((comp) => {
      let activeCustodiansCount = 0;
      for (const uc of (comp.users as any) || []) {
        if (uc.user?.custodianAccounts?.length) activeCustodiansCount += uc.user.custodianAccounts.length;
      }
      return { id: comp.id, name: comp.name, code: comp.code, currentBalance: companyStats[comp.id]?.bal || 0, inflow: companyStats[comp.id]?.inflow || 0, outflow: companyStats[comp.id]?.outflow || 0, activeCustodiansCount };
    });
    
    return { success: true, consolidatedBalance, inflow, outflow, netVelocity, companies: perCompanyPerformance, custodianExposure: topExposure };
  }

  async executeInterConcernTransfer(dto: { fromCompanyId: string, toCompanyId: string, fromWalletId: string, toWalletId: string, amount: number, note?: string }, reqUser: any) {
    if (!dto.fromWalletId || !dto.toWalletId) throw new BadRequestException('Source and destination wallets required');
    if (dto.amount <= 0) throw new BadRequestException('Amount must be greater than 0');
    return await this.prisma.$transaction(async (tx: any) => {
      const fromW = await tx.wallet.findUnique({ where: { id: dto.fromWalletId } });
      const toW = await tx.wallet.findUnique({ where: { id: dto.toWalletId } });
      if (!fromW || !toW) throw new BadRequestException('Invalid wallets');
      
      const uniquePrefix = Date.now().toString(36) + Math.random().toString(36).substr(2, 5);
      await tx.moneyMovement.create({ data: { idempotencyKey: `tx_out_${uniquePrefix}`, walletId: fromW.id, direction: 'out', amount: dto.amount, channel: 'cash', collectorId: reqUser?.id || reqUser?.sub, custodianId: fromW.custodianId, entryTag: 'INTER_COMPANY_TRANSFER', notes: dto.note || 'Inter-concern transfer out', occurredAt: new Date() } as any });
      await tx.moneyMovement.create({ data: { idempotencyKey: `tx_in_${uniquePrefix}`, walletId: toW.id, direction: 'in', amount: dto.amount, channel: 'cash', collectorId: reqUser?.id || reqUser?.sub, custodianId: toW.custodianId, entryTag: 'INTER_COMPANY_TRANSFER', notes: dto.note || 'Inter-concern transfer in', occurredAt: new Date() } as any });
      return { success: true, message: 'Inter-concern transfer completed successfully' };
    });
  }
}
