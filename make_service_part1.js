const fs = require('fs');
const content = `import { Injectable, BadRequestException, NotFoundException, ConflictException, ForbiddenException } from '@nestjs/common';
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

  async getOverview(tenantId: string, authorizedCompanyIds: string[], requestedCompanyId?: string, period: 'today' | 'week' | 'month' | 'all' = 'month') {
    if (!authorizedCompanyIds || authorizedCompanyIds.length === 0) {
      return { company: null, assignedConcerns: [], velocity: { inflow: 0, outflow: 0 }, recentTransactions: [], topEmployees: [] };
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
`;
fs.writeFileSync('backend/src/modules/manager/manager.service.ts', content, 'utf8');
console.log('Part 1 done');
