import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  console.log('--- REPAIRING LEDGER & SEGMENT DATA ---');

  // 1. Ensure at least one default ledger exists
  let defaultLedger = await prisma.ledger.findFirst({
    where: { code: 'GEN-OPS' },
  });

  if (!defaultLedger) {
    const tenant = await prisma.company.findFirst();
    const tenantId = tenant?.tenantId || 'default-tenant';
    defaultLedger = await prisma.ledger.create({
      data: {
        tenantId,
        name: 'General Operations',
        code: 'GEN-OPS',
        isPerpetual: true,
        status: 'ACTIVE',
      },
    });
  }

  // 2. Migrate existing TransactionCategory records into Segments if Segment is empty
  const existingCategories = await prisma.transactionCategory.findMany();
  console.log(`Found ${existingCategories.length} existing transaction categories.`);

  for (const cat of existingCategories) {
    const existingSeg = await prisma.segment.findFirst({
      where: { name: cat.name },
    });
    if (!existingSeg) {
      await prisma.segment.create({
        data: {
          ledgerId: defaultLedger.id,
          name: cat.name,
        },
      });
      console.log(`Migrated category "${cat.name}" into Segment under General Operations.`);
    }
  }

  // 3. Link all MoneyMovements to Ledgers and Segments
  const movements = await prisma.moneyMovement.findMany();
  console.log(`Linking ${movements.length} money movements...`);

  for (const m of movements) {
    let ledgerId = m.ledgerId || defaultLedger.id;
    let segmentId = m.segmentId;

    if (!segmentId) {
      const meta = (m.metadata as any) || {};
      const targetName = m.notes?.trim() || meta.category || 'General Operations';

      let seg = await prisma.segment.findFirst({
        where: { name: { contains: targetName, mode: 'insensitive' } },
      });

      if (!seg) {
        seg = await prisma.segment.create({
          data: {
            ledgerId: ledgerId,
            name: targetName,
          },
        });
      }

      segmentId = seg.id;
      ledgerId = seg.ledgerId || ledgerId;
    }

    await prisma.moneyMovement.update({
      where: { id: m.id },
      data: {
        ledgerId: ledgerId,
        segmentId: segmentId,
      },
    });
  }

  console.log('--- REPAIR COMPLETE: All movements now linked to Ledgers and Segments ---');
}

main()
  .catch((e) => console.error(e))
  .finally(() => prisma.$disconnect());


