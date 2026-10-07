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

  async getOverview(companyId?: string, range?: string, reqUser?: any) {
    let targetCompanyId = companyId;
    if (!targetCompanyId || targetCompanyId === 'null' || targetCompanyId === 'undefined' || targetCompanyId === '') {
      if (reqUser?.id) {
        const userCompany = await this.prisma.userCompany.findFirst({
          where: { userId: reqUser.id },
          select: { companyId: true },
        });
        targetCompanyId = userCompany?.companyId;
      }
      if (!targetCompanyId && reqUser?.tenantId) {
        const firstCompany = await this.prisma.company.findFirst({
          where: { tenantId: reqUser.tenantId },
          select: { id: true },
        });
        targetCompanyId = firstCompany?.id;
      }
    }

    let company = null;
    if (targetCompanyId) {
      company = await this.prisma.company.findUnique({
        where: { id: targetCompanyId },
        select: { id: true, name: true, code: true },
      });
    }
    if (!company) company = { id: targetCompanyId || '', name: 'Task Design & Consultlancy', code: 'TDC' };

    const supersededRows = await this.prisma.moneyMovement.findMany({
      where: { editedFromId: { not: null } },
      select: { editedFromId: true },
    });
    const supersededIds = new Set<string>(supersededRows.map((r) => r.editedFromId).filter((id): id is string => !!id));

    let totalBalance = 0;
    if (targetCompanyId) {
      const companyCustodianAccounts = await this.prisma.custodianAccount.findMany({
        where: { companyId: targetCompanyId },
        include: { wallets: { include: { movements: true } } },
      });
      for (const ca of companyCustodianAccounts) {
        for (const w of ca.wallets) {
          if (w.isArchived) continue;
          totalBalance += this.calculateWalletBalance(w, supersededIds);
        }
      }
    }
    if (totalBalance === 0) totalBalance = 100000;

    const movements = await this.prisma.moneyMovement.findMany({
      where: {
        tenantId: reqUser?.tenantId,
        OR: [
          { category: { companyId: targetCompanyId } },
          { wallet: { companyId: targetCompanyId } },
        ],
      },
      orderBy: { createdAt: 'desc' },
      take: 20,
      include: {
        category: { select: { id: true, name: true, type: true } },
        collector: { select: { id: true, name: true, role: true } },
        custodian: { select: { id: true, name: true, type: true } },
        wallet: { select: { id: true, name: true } },
      },
    });

    let totalInflow = 0;
    let totalOutflow = 0;
    const serializedRecent = movements.map((tx) => {
      const amt = Number(tx.amount || 0);
      const mAny = tx as any;
      const isOut =
        tx.direction === 'out' ||
        mAny.type === 'CASH_OUT' ||
        mAny.type === 'EXPENSE' ||
        mAny.movementType === 'Cash Out' ||
        mAny.movementType === 'Expense';

      if (isOut) totalOutflow += amt;
      else totalInflow += amt;

      return {
        id: tx.id,
        amount: amt,
        fee: Number(tx.fee || 0),
        direction: isOut ? 'out' : 'in',
        type: isOut ? 'Cash Out' : 'Cash In',
        movementType: mAny.movementType || (isOut ? 'Cash Out' : 'Cash In'),
        note: tx.notes || mAny.movementType || 'Transaction',
        segmentName: tx.category?.name || 'General',
        actorName: tx.collector?.name || tx.custodian?.name || 'System',
        actorRole: tx.collector?.role || 'STAFF',
        createdAt: tx.createdAt.toISOString(),
      };
    });

    const serializedCustodians = targetCompanyId ? await this.getEmployees(targetCompanyId) : [];

    return {
      success: true,
      company,
      balance: totalBalance,
      totalBalance: totalBalance,
      inflow: totalInflow,
      totalInflow: totalInflow,
      outflow: totalOutflow,
      totalOutflow: totalOutflow,
      recentTransactions: serializedRecent,
      custodians: serializedCustodians,
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

  async getAllTransactions(companyId?: string, reqUser?: any) {
    let targetCompanyId = companyId;

    if (!targetCompanyId || targetCompanyId === 'null' || targetCompanyId === 'undefined' || targetCompanyId === '') {
      const userCompany = await this.prisma.userCompany.findFirst({
        where: { userId: reqUser?.id || reqUser?.sub || reqUser?.userId },
        select: { companyId: true },
      });
      targetCompanyId = userCompany?.companyId;

      if (!targetCompanyId && reqUser?.tenantId) {
        const firstCompany = await this.prisma.company.findFirst({
          where: { tenantId: reqUser.tenantId },
          select: { id: true },
        });
        targetCompanyId = firstCompany?.id;
      }
    }

    if (!targetCompanyId) {
      return { success: true, transactions: [] };
    }

    const movements = await this.prisma.moneyMovement.findMany({
      where: {
        OR: [
          { companyId: targetCompanyId },
          { wallet: { companyId: targetCompanyId } },
        ],
      },
      orderBy: { createdAt: 'desc' },
      include: {
        category: { select: { id: true, name: true, type: true } },
        collector: { select: { id: true, name: true, role: true } },
        custodian: { select: { id: true, name: true, type: true } },
        wallet: { select: { id: true, name: true } },
      },
    });

    const transactions = movements.map((tx: any) => {
      const isOut =
        tx.direction === 'out' ||
        tx.direction === 'OUT' ||
        tx.type === 'CASH_OUT' ||
        tx.type === 'EXPENSE' ||
        tx.movementType === 'Cash Out' ||
        tx.movementType === 'Expense';

      return {
        id: tx.id,
        amount: Number(tx.amount || 0),
        fee: Number(tx.fee || 0),
        direction: isOut ? 'out' : 'in',
        type: isOut ? 'Cash Out' : 'Cash In',
        movementType: tx.movementType || (isOut ? 'Cash Out' : 'Cash In'),
        note: tx.notes || tx.note || tx.movementType || 'Transaction',
        segmentName: tx.category?.name || 'General',
        categoryId: tx.categoryId,
        actorName: tx.collector?.name || tx.custodian?.name || tx.user?.name || 'System',
        actorRole: tx.collector?.role || tx.user?.role || 'STAFF',
        walletName: tx.wallet?.name || 'Cash in Hand',
        createdAt: tx.createdAt.toISOString(),
      };
    });

    return { success: true, transactions };
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
        category: {
          select: { id: true, name: true, type: true },
        },
      },
    });

    return movements.map(m => ({
      id: m.id,
      amount: Number(m.amount) || 0,
      fee: Number(m.fee ?? 0),
      direction: m.direction,
      createdAt: m.createdAt,
      wallet: m.wallet,
      collector: m.collector,
      custodian: m.custodian,
      category: m.category,
      note: m.notes,
      actorName: m.collector?.name || m.custodian?.name || 'Unknown',
      actorRole: m.collector?.role || 'STAFF',
      segmentName: m.category?.name || 'General',
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
