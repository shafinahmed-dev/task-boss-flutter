/**
 * End-to-End Test: Critical Ledger Flow
 *
 * Tests the complete critical path:
 *   1. Collector logs in and obtains JWT.
 *   2. Collector logs an offline money IN movement.
 *   3. Sync engine posts to POST /ledger/movements with idempotency key.
 *   4. Collector initiates custody handover to Accounts custodian.
 *   5. Accounts user confirms transfer.
 *   6. Verify GET /ledger/custodians/:id/balance reflects exact balance
 *      transition for both custodians.
 */
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication, ValidationPipe } from '@nestjs/common';
import request from 'supertest';
import { AppModule } from '../src/app.module.js';
import { PrismaService } from '../src/database/prisma.service.js';
import { AuthService } from '../src/modules/auth/auth.service.js';

describe('Ledger Flow (e2e)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let authService: AuthService;

  // Test fixtures
  let companyId: string;
  let secondCompanyId: string;
  let collectorUserId: string;
  let accountsUserId: string;
  let collectorCustodianId: string;
  let accountsCustodianId: string;
  let collectorToken: string;
  let accountsToken: string;

  beforeAll(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    app.useGlobalPipes(new ValidationPipe({ transform: true }));
    await app.init();

    prisma = app.get(PrismaService);
    authService = app.get(AuthService);

    // Clean test data
    await cleanupTestData();

    // Seed test data
    await seedTestData();
  });

  afterAll(async () => {
    await cleanupTestData();
    await app.close();
  });

  // ── Helper: cleanup test data ────────────────────────────────────────────

  async function cleanupTestData() {
    // Delete in reverse FK order
    await prisma.$executeRaw`DELETE FROM "inter_company_allocations"`;
    await prisma.custodyTransfer.deleteMany();
    await prisma.digitalReceipt.deleteMany();
    await prisma.moneyMovement.deleteMany();
    await prisma.custodianAccount.deleteMany();
    await prisma.receiptNumberBlock.deleteMany();
    await prisma.userCompany.deleteMany();
    await prisma.user.deleteMany();
    await prisma.company.deleteMany();
  }

  // ── Helper: seed test data ───────────────────────────────────────────────

  async function seedTestData() {
    // Create two companies (for multi-entity isolation testing)
    const [company, secondCompany] = await Promise.all([
      prisma.company.create({
        data: { name: 'TASK Group BD' },
      }),
      prisma.company.create({
        data: { name: 'TASK Group MY' },
      }),
    ]);
    companyId = company.id;
    secondCompanyId = secondCompany.id;

    // Create collector user (linked to companyId only)
    const collectorUser = await authService.createUser({
      name: 'Test Collector',
      role: 'collector',
      password: 'collector123',
      companyIds: [companyId],
    });
    collectorUserId = collectorUser.id;

    // Create accounts user (linked to companyId)
    const accountsUser = await authService.createUser({
      name: 'Test Accounts',
      role: 'accounts',
      password: 'accounts123',
      companyIds: [companyId],
    });
    accountsUserId = accountsUser.id;

    // Create custodian accounts
    const [collectorCustodian, accountsCustodian] = await Promise.all([
      prisma.custodianAccount.create({
        data: {
          companyId,
          type: 'person',
          name: 'Collector Custodian',
          linkedUserId: collectorUserId,
        },
      }),
      prisma.custodianAccount.create({
        data: {
          companyId,
          type: 'drawer',
          name: 'Office Drawer',
          linkedUserId: accountsUserId,
        },
      }),
    ]);
    collectorCustodianId = collectorCustodian.id;
    accountsCustodianId = accountsCustodian.id;
  }

  // ── Step 1: Collector logs in and obtains JWT ────────────────────────────

  describe('Step 1: Authentication', () => {
    it('POST /auth/login — collector obtains JWT', async () => {
      const response = await request(app.getHttpServer())
        .post('/auth/login')
        .send({
          email: 'Test Collector',
          password: 'collector123',
        })
        .expect(200);

      expect(response.body).toHaveProperty('access_token');
      expect(response.body.user).toMatchObject({
        name: 'Test Collector',
        role: 'collector',
      });
      expect(response.body.user.companyIds).toContain(companyId);

      collectorToken = response.body.access_token;
    });

    it('POST /auth/login — accounts user obtains JWT', async () => {
      const response = await request(app.getHttpServer())
        .post('/auth/login')
        .send({
          email: 'Test Accounts',
          password: 'accounts123',
        })
        .expect(200);

      expect(response.body).toHaveProperty('access_token');
      accountsToken = response.body.access_token;
    });

    it('POST /auth/login — invalid credentials rejected', async () => {
      await request(app.getHttpServer())
        .post('/auth/login')
        .send({
          email: 'Test Collector',
          password: 'wrongpassword',
        })
        .expect(401);
    });
  });

  // ── Step 2 & 3: Collector logs money IN movement ─────────────────────────

  describe('Step 2-3: Record Money Movement', () => {
    it('POST /ledger/movements — collector records money IN', async () => {
      const idempotencyKey = crypto.randomUUID();

      const response = await request(app.getHttpServer())
        .post('/ledger/movements')
        .set('Authorization', `Bearer ${collectorToken}`)
        .send({
          companyId,
          idempotencyKey,
          direction: 'in',
          amount: 50000,
          channel: 'cash',
          collectorId: collectorUserId,
          custodianId: collectorCustodianId,
          entryTag: 'client_payment',
          occurredAt: new Date().toISOString(),
        })
        .expect(201);

      expect(response.body.id).toBeDefined();
      expect(response.body.direction).toBe('in');
      expect(Number(response.body.amount)).toBe(50000);
      expect(response.body.idempotencyKey).toBe(idempotencyKey);
    });

    it('POST /ledger/movements — idempotency prevents duplicate', async () => {
      const idempotencyKey = crypto.randomUUID();

      // First request
      const first = await request(app.getHttpServer())
        .post('/ledger/movements')
        .set('Authorization', `Bearer ${collectorToken}`)
        .send({
          companyId,
          idempotencyKey,
          direction: 'in',
          amount: 25000,
          channel: 'bkash',
          collectorId: collectorUserId,
          custodianId: collectorCustodianId,
          entryTag: 'loan_received',
          occurredAt: new Date().toISOString(),
        })
        .expect(201);

      // Second request with same key — should return same record
      const second = await request(app.getHttpServer())
        .post('/ledger/movements')
        .set('Authorization', `Bearer ${collectorToken}`)
        .send({
          companyId,
          idempotencyKey,
          direction: 'in',
          amount: 99999, // different amount — should be ignored
          channel: 'bank',
          collectorId: collectorUserId,
          custodianId: collectorCustodianId,
          entryTag: 'loan_received',
          occurredAt: new Date().toISOString(),
        })
        .expect(201);

      expect(first.body.id).toBe(second.body.id);
      expect(Number(second.body.amount)).toBe(25000); // original amount preserved
    });
  });

  // ── Verify collector balance before handover ──────────────────────────────

  describe('Step 4a: Collector Balance Verification', () => {
    it('GET /ledger/custodians/:id/balance — collector has IN total', async () => {
      const response = await request(app.getHttpServer())
        .get(`/ledger/custodians/${collectorCustodianId}/balance`)
        .query({ companyId })
        .set('Authorization', `Bearer ${collectorToken}`)
        .expect(200);

      expect(response.body.custodianId).toBe(collectorCustodianId);
      // 50000 + 25000 = 75000
      expect(response.body.totalIn).toBe(75000);
      expect(response.body.totalOut).toBe(0);
      expect(response.body.netBalance).toBe(75000);
    });
  });

  // ── Step 4: Collector initiates custody handover ──────────────────────────

  describe('Step 4: Custody Handover', () => {
    it('POST /custody/transfers — collector initiates handover', async () => {
      const response = await request(app.getHttpServer())
        .post('/custody/transfers')
        .set('Authorization', `Bearer ${collectorToken}`)
        .send({
          companyId,
          idempotencyKey: crypto.randomUUID(),
          fromCustodianId: collectorCustodianId,
          toCustodianId: accountsCustodianId,
          amount: 75000,
        })
        .expect(201);

      expect(response.body.status).toBe('pending');
      expect(response.body.fromCustodianId).toBe(collectorCustodianId);
      expect(response.body.toCustodianId).toBe(accountsCustodianId);
    });
  });

  // ── Step 5: Accounts user confirms transfer ──────────────────────────────

  describe('Step 5: Confirm Transfer', () => {
    it('POST /custody/transfers/:id/confirm — accounts confirms', async () => {
      // Get the pending transfer
      const pendingTransfer = await prisma.custodyTransfer.findFirst({
        where: {
          fromCustodianId: collectorCustodianId,
          toCustodianId: accountsCustodianId,
          status: 'pending',
        },
      });
      expect(pendingTransfer).toBeDefined();

      const response = await request(app.getHttpServer())
        .post(`/custody/transfers/${pendingTransfer!.id}/confirm`)
        .set('Authorization', `Bearer ${accountsToken}`)
        .expect(200);

      expect(response.body.status).toBe('confirmed');
      expect(response.body.confirmedAt).toBeDefined();
    });
  });

  // ── Step 6: Verify balances ──────────────────────────────────────────────

  describe('Step 6: Balance Verification', () => {
    it('GET /ledger/custodians/:id/balance — collector balance zeroed', async () => {
      const response = await request(app.getHttpServer())
        .get(`/ledger/custodians/${collectorCustodianId}/balance`)
        .query({ companyId })
        .set('Authorization', `Bearer ${collectorToken}`)
        .expect(200);

      expect(response.body.custodianId).toBe(collectorCustodianId);
      expect(response.body.totalIn).toBe(75000);
      expect(response.body.totalOut).toBe(0);
      expect(response.body.confirmedTransferOut).toBe(75000);
      // 75000 - 75000 = 0
      expect(response.body.netBalance).toBe(0);
    });

    it('GET /ledger/custodians/:id/balance — accounts balance reflects transfer', async () => {
      const response = await request(app.getHttpServer())
        .get(`/ledger/custodians/${accountsCustodianId}/balance`)
        .query({ companyId })
        .set('Authorization', `Bearer ${accountsToken}`)
        .expect(200);

      expect(response.body.custodianId).toBe(accountsCustodianId);
      expect(response.body.totalIn).toBe(0);
      expect(response.body.totalOut).toBe(0);
      expect(response.body.confirmedTransferIn).toBe(75000);
      expect(response.body.confirmedTransferOut).toBe(0);
      // 0 + 75000 = 75000
      expect(response.body.netBalance).toBe(75000);
    });
  });

  // ── Multi-entity isolation test ──────────────────────────────────────────

  describe('Multi-Entity Isolation', () => {
    it('GET /ledger/custodians/:id/balance — wrong companyId returns 403', async () => {
      await request(app.getHttpServer())
        .get(`/ledger/custodians/${collectorCustodianId}/balance`)
        .query({ companyId: secondCompanyId }) // wrong company
        .set('Authorization', `Bearer ${collectorToken}`)
        .expect(403);
    });
  });

  // ── Unauthorized access test ─────────────────────────────────────────────

  describe('Authentication Enforcement', () => {
    it('GET /ledger/custodians/:id/balance — no token returns 401', async () => {
      await request(app.getHttpServer())
        .get(`/ledger/custodians/${collectorCustodianId}/balance`)
        .query({ companyId })
        .expect(401);
    });

    it('POST /ledger/movements — no token returns 401', async () => {
      await request(app.getHttpServer())
        .post('/ledger/movements')
        .send({
          companyId,
          idempotencyKey: crypto.randomUUID(),
          direction: 'in',
          amount: 1000,
          channel: 'cash',
          collectorId: collectorUserId,
          custodianId: collectorCustodianId,
          entryTag: 'client_payment',
          occurredAt: new Date().toISOString(),
        })
        .expect(401);
    });
  });

  // ── Movement edit test ───────────────────────────────────────────────────

  describe('Movement Edit (Append-Only)', () => {
    it('POST /ledger/movements/:id/edit — correction row created', async () => {
      // Find the first movement
      const movement = await prisma.moneyMovement.findFirst({
        where: {
          custodianId: collectorCustodianId,
          entryTag: 'client_payment',
        },
      });
      expect(movement).toBeDefined();

      const response = await request(app.getHttpServer())
        .post(`/ledger/movements/${movement!.id}/edit`)
        .set('Authorization', `Bearer ${collectorToken}`)
        .send({
          amount: 55000, // corrected amount
        })
        .expect(201);

      expect(response.body.editedFromId).toBe(movement!.id);
      expect(Number(response.body.amount)).toBe(55000);

      // Verify original still exists (append-only)
      const original = await prisma.moneyMovement.findUnique({
        where: { id: movement!.id },
      });
      expect(original).toBeDefined();
      expect(Number(original!.amount)).toBe(50000); // original unchanged
    });
  });

  // ── Ledger history test ──────────────────────────────────────────────────

  describe('Ledger History', () => {
    it('GET /ledger/custodians/:id/movements — paginated history', async () => {
      const response = await request(app.getHttpServer())
        .get(`/ledger/custodians/${collectorCustodianId}/movements`)
        .query({ page: 1, limit: 10 })
        .set('Authorization', `Bearer ${collectorToken}`)
        .expect(200);

      expect(response.body.items).toBeDefined();
      expect(Array.isArray(response.body.items)).toBe(true);
      expect(response.body.total).toBeGreaterThanOrEqual(2);
      expect(response.body.page).toBe(1);
    });
  });
});