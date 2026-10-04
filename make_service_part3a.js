const fs = require('fs');
const content = `
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
`;
fs.appendFileSync('backend/src/modules/manager/manager.service.ts', content, 'utf8');
console.log('Part 3a done');
