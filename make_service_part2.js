const fs = require('fs');
const content = `
    const targetComp = assignedCompanies.find(c => c.id === targetCompanyId) || assignedCompanies[0];
    if (!targetComp) {
      return { company: null, assignedConcerns, velocity: { inflow: 0, outflow: 0 }, recentTransactions: [], topEmployees: [] };
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
    };
  }
`;
fs.appendFileSync('backend/src/modules/manager/manager.service.ts', content, 'utf8');
console.log('Part 2 done');
