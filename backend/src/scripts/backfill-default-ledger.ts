import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function backfill() {
  console.log('Starting default ledger backfill...');
  const tenants = await prisma.tenant.findMany();
  for (const tenant of tenants) {
    // Check if default ledger exists
    let defaultLedger = await prisma.ledger.findFirst({
      where: { tenantId: tenant.id, code: 'GEN-OPS' },
    });

    if (!defaultLedger) {
      defaultLedger = await prisma.ledger.create({
        data: {
          tenantId: tenant.id,
          name: 'General Operations',
          code: 'GEN-OPS',
          description: 'Default backfilled general operations ledger',
          isPerpetual: true,
          status: 'ACTIVE',
        },
      });
      console.log(`Created default ledger 'GEN-OPS' for tenant ${tenant.id}`);
    }

    // Assign all active managers in tenant to this ledger
    const managers = await prisma.user.findMany({
      where: { tenantId: tenant.id, role: { in: ['MANAGER', 'manager'] } },
    });

    for (const mgr of managers) {
      await prisma.ledgerMember.upsert({
        where: {
          ledgerId_userId: {
            ledgerId: defaultLedger.id,
            userId: mgr.id,
          },
        },
        update: {},
        create: {
          ledgerId: defaultLedger.id,
          userId: mgr.id,
          role: 'MANAGER',
        },
      });
    }

    // Backfill segments without ledgerId
    await prisma.segment.updateMany({
      where: { ledgerId: undefined },
      data: { ledgerId: defaultLedger.id },
    }).catch(() => {});

    // Backfill money movements without ledgerId
    await prisma.moneyMovement.updateMany({
      where: { ledgerId: null },
      data: { ledgerId: defaultLedger.id },
    });

    console.log(`Backfilled tenant ${tenant.id} successfully.`);
  }
  console.log('Backfill complete.');
}

backfill()
  .catch((e) => {
    console.error('Backfill error:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
