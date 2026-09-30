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
  await prisma.tenant.deleteMany();

  console.log('Seeding Database...');

  // 1. Create Default Tenant
  const tenant = await prisma.tenant.create({
    data: {
      name: 'TASK Group',
      slug: 'taskgroup',
    }
  });
  console.log(`Created Tenant: ${tenant.name} (${tenant.slug})`);

  // 2. Create Company for Tenant
  const company = await prisma.company.create({
    data: {
      name: 'TASK Engineering Ltd.',
      tenantId: tenant.id,
      code: 'TASK',
    },
  });
  console.log(`Created Company: ${company.name} (${company.id})`);

  // 3. Create Suite Admin
  const suitePassword = await bcrypt.hash('TaskSuite2026!', 10);
  const suiteUser = await prisma.user.create({
    data: {
      handle: 'suite.taskgroup',
      name: 'TASK Group Suite',
      email: 'suite@taskgroup.com',
      role: 'SUITE_ADMIN',
      tenantId: tenant.id,
      passwordHash: suitePassword,
      languagePref: 'en',
    }
  });
  await prisma.userCompany.create({ data: { userId: suiteUser.id, companyId: company.id } });
  
  // 4. Create Manager
  const managerPassword = await bcrypt.hash('TaskMan2026!', 10);
  const managerUser = await prisma.user.create({
    data: {
      handle: 'ceoman.taskgroup',
      name: 'Managing Director',
      email: 'ceo@taskgroup.com',
      designation: 'CEO',
      department: 'Executive',
      role: 'MANAGER',
      tenantId: tenant.id,
      passwordHash: managerPassword,
      languagePref: 'en',
    }
  });
  await prisma.userCompany.create({ data: { userId: managerUser.id, companyId: company.id } });
  const managerCustodian = await prisma.custodianAccount.create({
    data: {
      name: 'CEO Vault',
      type: 'person',
      companyId: company.id,
      linkedUserId: managerUser.id,
    }
  });
  await prisma.wallet.create({
    data: {
      custodianId: managerCustodian.id,
      companyId: company.id,
      name: 'Cash in Hand',
      type: 'CASH',
      isDefault: true,
    }
  });

  // 5. Create Employee
  const employeePassword = await bcrypt.hash('TaskEmp2026!', 10);
  const employeeUser = await prisma.user.create({
    data: {
      handle: 'shafinahmed.taskgroup',
      name: 'Shafin Ahmed',
      email: 'shafin@taskgroup.com',
      designation: 'Digital Marketer',
      department: 'Marketing',
      role: 'EMPLOYEE',
      tenantId: tenant.id,
      passwordHash: employeePassword,
      languagePref: 'en',
    }
  });
  await prisma.userCompany.create({ data: { userId: employeeUser.id, companyId: company.id } });
  const employeeCustodian = await prisma.custodianAccount.create({
    data: {
      name: 'Shafin Ahmed / Cash',
      type: 'person',
      companyId: company.id,
      linkedUserId: employeeUser.id,
    }
  });
  const shafinWallet = await prisma.wallet.create({
    data: {
      custodianId: employeeCustodian.id,
      companyId: company.id,
      name: 'Cash in Hand',
      type: 'CASH',
      isDefault: true,
    }
  });

  // 6. Initial Ledger Balances (Optional but helpful for testing)
  await prisma.moneyMovement.create({
    data: {
      idempotencyKey: crypto.randomUUID(),
      direction: 'in',
      amount: 50000,
      currency: 'BDT',
      channel: 'cash',
      collectorId: employeeUser.id,
      custodianId: employeeCustodian.id,
      walletId: shafinWallet.id,
      occurredAt: new Date(),
      syncStatus: 'synced',
    },
  });

  console.log('\n=== SEED SUMMARY & CREDENTIALS ===');
  console.log(`Tenant Slug: taskgroup`);
  console.log(`Suite Admin: suite.taskgroup     | Password: TaskSuite2026!`);
  console.log(`Manager:     ceoman.taskgroup    | Password: TaskMan2026!`);
  console.log(`Employee:    shafinahmed.taskgroup| Password: TaskEmp2026! (Balance: ৳50,000)`);
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
