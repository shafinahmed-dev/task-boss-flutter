import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  console.log('--- Starting Ledger Segments Sync ---');

  const ledgers = await prisma.ledger.findMany();
  if (ledgers.length === 0) {
    console.log('No ledgers found.');
    return;
  }

  const movements = await prisma.moneyMovement.findMany({
    include: { segment: true, ledger: true },
  });

  console.log(`Found ${movements.length} total movements.`);

  for (const m of movements) {
    let ledgerId = m.ledgerId;
    if (!ledgerId) {
      ledgerId = ledgers[0].id;
      await prisma.moneyMovement.update({
        where: { id: m.id },
        data: { ledgerId },
      });
    }

    if (!m.segmentId) {
      const meta = (m.metadata as any) || {};
      const segName = (m as any).notes?.trim() || meta.category || 'General Operations';

      let segment = await prisma.segment.findFirst({
        where: { ledgerId, name: segName },
      });

      if (!segment) {
        segment = await prisma.segment.create({
          data: {
            ledgerId,
            name: segName,
          },
        });
        console.log(`Created segment "${segName}" under ledger ${ledgerId}`);
      }

      await prisma.moneyMovement.update({
        where: { id: m.id },
        data: { segmentId: segment.id },
      });
    }
  }

  console.log('--- Ledger Segments Sync Completed ---');
}

main()
  .catch((e) => console.error(e))
  .finally(() => prisma.$disconnect());



