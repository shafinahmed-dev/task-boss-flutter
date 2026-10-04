import { Injectable, BadRequestException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { PrismaService } from '../../database/prisma.service.js';

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
                    wallets: { include: { movements: true } },
                  },
                },
              },
            },
          },
        },
      },
    });

    // Simplified aggregation (reusing logic from SuiteService)
    let totalBalance = 0;
    let inflows = 0;
    let outflows = 0;

    for (const company of companies) {
      for (const u of company.users) {
        for (const ca of u.user.custodianAccounts) {
          for (const w of ca.wallets) {
             // ... calculate totals
          }
        }
      }
    }

    return { totalBalance, inflows, outflows };
  }

  async provisionEmployee(tenantId: string, managerId: string, dto: any) {
    // Validate manager can access companyId
    // ...
    // Create user with bcrypt hash of password
  }
}
