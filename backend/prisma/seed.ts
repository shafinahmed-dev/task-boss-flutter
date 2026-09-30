import { PrismaClient } from '@prisma/client';
import * as bcrypt from 'bcryptjs';

const prisma = new PrismaClient();

async function main() {
  console.log('Clearing existing data...');
  await prisma.digitalReceipt.deleteMany();
  await prisma.receiptNumberBlock.deleteMany();
  await prisma.custodyTransfer.deleteMany();
  await prisma.moneyMovement.deleteMany();
  await prisma.wallet.deleteMany();
  await prisma.project.deleteMany();
  await prisma.client.deleteMany();
  await prisma.custodianAccount.deleteMany();
  await prisma.userCompany.deleteMany();
  await prisma.user.deleteMany();
  await prisma.company.deleteMany();

  console.log('Seeding Database...');

  // 1. Create Company
  const company = await prisma.company.create({
    data: {
      name: 'TASK Engineering Ltd.',
    },
  });
  console.log(`Created Company: ${company.name} (${company.id})`);

  // 2. Create User (Collector)
  const passwordHash = await bcrypt.hash('Password123!', 10);
  const collector = await prisma.user.create({
    data: {
      name: 'Collector User',
      email: 'collector@task.com',
      role: 'collector',
      passwordHash,
      languagePref: 'en',
    },
  });
  console.log(`Created User: ${collector.name} (${collector.id})`);

  // 3. UserCompany link
  await prisma.userCompany.create({
    data: {
      userId: collector.id,
      companyId: company.id,
    },
  });
  console.log('Linked User to Company');

  // 4. CustodianAccount
  const custodian = await prisma.custodianAccount.create({
    data: {
      name: 'Collector Wallet / Cash',
      type: 'person', // from schema (person | drawer | bank | wallet | project_cash)
      companyId: company.id,
      linkedUserId: collector.id,
    },
  });
  console.log(`Created CustodianAccount for Collector (${custodian.id})`);
  // 4b. Create initial Wallets for Collector
  const collectorCashWallet = await prisma.wallet.create({
    data: {
      custodianId: custodian.id,
      companyId: company.id,
      name: 'Cash in Hand',
      type: 'CASH',
      isDefault: true,
    },
  });
  await prisma.wallet.create({
    data: {
      custodianId: custodian.id,
      companyId: company.id,
      name: 'bKash Personal',
      type: 'MFS',
      institution: 'bKash',
      accountNumber: '017XXXXXXXX',
      isDefault: false,
    },
  });
  await prisma.wallet.create({
    data: {
      custodianId: custodian.id,
      companyId: company.id,
      name: 'City Bank A/C',
      type: 'BANK',
      institution: 'City Bank',
      accountNumber: '110XXXXXXX',
      isDefault: false,
    },
  });

  // 5. ReceiptNumberBlock
  const block = await prisma.receiptNumberBlock.create({
    data: {
      prefix: 'REC',
      rangeStart: 1000,
      rangeEnd: 2000,
      currentPointer: 999, // next will be 1000
      status: 'active',
      companyId: company.id,
      assignedToUserId: collector.id,
    },
  });
  console.log(`Created ReceiptNumberBlock: ${block.prefix}-${block.rangeStart} to ${block.rangeEnd}`);

  // Create User (Accounts)
  const accountsUser = await prisma.user.create({
    data: {
      name: 'Accounts User',
      email: 'accounts@task.com',
      role: 'accounts',
      passwordHash,
      languagePref: 'en',
    },
  });
  console.log(`Created User: ${accountsUser.name} (${accountsUser.id})`);

  await prisma.userCompany.create({
    data: {
      userId: accountsUser.id,
      companyId: company.id,
    },
  });

  const accountsCustodian = await prisma.custodianAccount.create({
    data: {
      name: 'Accounts Vault / Safe',
      type: 'drawer',
      companyId: company.id,
      linkedUserId: accountsUser.id,
    },
  });
  console.log(`Created CustodianAccount for Accounts (${accountsCustodian.id})`);

  const accountsCashWallet = await prisma.wallet.create({
    data: {
      custodianId: accountsCustodian.id,
      companyId: company.id,
      name: 'Cash in Hand',
      type: 'CASH',
      isDefault: true,
    },
  });
  await prisma.wallet.create({
    data: {
      custodianId: accountsCustodian.id,
      companyId: company.id,
      name: 'bKash Personal',
      type: 'MFS',
      institution: 'bKash',
      accountNumber: '017XXXXXXXX',
      isDefault: false,
    },
  });
  await prisma.wallet.create({
    data: {
      custodianId: accountsCustodian.id,
      companyId: company.id,
      name: 'City Bank A/C',
      type: 'BANK',
      institution: 'City Bank',
      accountNumber: '110XXXXXXX',
      isDefault: false,
    },
  });

  // 6. Initial Ledger Balances
  await prisma.moneyMovement.create({
    data: {
      idempotencyKey: crypto.randomUUID(),
      direction: 'in',
      amount: 50000,
      currency: 'BDT',
      channel: 'cash',
      collectorId: collector.id,
      custodianId: custodian.id,
      walletId: collectorCashWallet.id,
      entryTag: 'client_payment',
      occurredAt: new Date(),
      syncStatus: 'synced',
    },
  });

  await prisma.moneyMovement.create({
    data: {
      idempotencyKey: crypto.randomUUID(),
      direction: 'in',
      amount: 85000,
      currency: 'BDT',
      channel: 'cash',
      collectorId: accountsUser.id,
      custodianId: accountsCustodian.id,
      walletId: accountsCashWallet.id,
      entryTag: 'client_payment',
      occurredAt: new Date(),
      syncStatus: 'synced',
    },
  });

  console.log('\n=== SEED SUMMARY & CREDENTIALS ===');
  console.log(`Company ID: ${company.id} (${company.name})`);
  console.log(`Collector User: collector@task.com | Password: Password123! | Custodian ID: ${custodian.id} (Balance: ৳50,000)`);
  console.log(`Accounts User: accounts@task.com  | Password: Password123! | Custodian ID: ${accountsCustodian.id} (Balance: ৳85,000)`);
  console.log('===================================\n');

  console.log('Seeding finished successfully.');

}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });