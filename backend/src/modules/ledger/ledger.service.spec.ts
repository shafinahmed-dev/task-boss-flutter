import { Test, TestingModule } from '@nestjs/testing';
import { LedgerService } from './ledger.service.js';
import { PrismaService } from '../../database/prisma.service.js';

// ── Minimal Prisma mock ──────────────────────────────────────────────────

function createPrismaMock() {
  return {
    moneyMovement: {
      findMany: vi.fn(),
      findUnique: vi.fn(),
      aggregate: vi.fn(),
      groupBy: vi.fn(),
      create: vi.fn(),
    },
    custodyTransfer: {
      aggregate: vi.fn(),
    },
  } as any;
}

// ── Test suite ───────────────────────────────────────────────────────────

describe('LedgerService', () => {
  let service: LedgerService;
  let prisma: ReturnType<typeof createPrismaMock>;

  beforeEach(async () => {
    prisma = createPrismaMock();

    const module: TestingModule = await Test.createTestingModule({
      providers: [
        LedgerService,
        { provide: PrismaService, useValue: prisma },
      ],
    }).compile();

    service = module.get(LedgerService);
  });

  // ───────────────────────────────────────────────────────────────────────

  describe('getCustodianBalance', () => {
    const custodianId = 'cust-1';
    const companyId = 'comp-1';

    beforeEach(() => {
      // Default: no superseded rows
      prisma.moneyMovement.findMany.mockResolvedValue([]);
      // Default: no confirmed transfers
      prisma.custodyTransfer.aggregate.mockResolvedValue({
        _sum: { amount: null },
      });
    });

    it('should increase balance for IN movements', async () => {
      prisma.moneyMovement.groupBy
        .mockResolvedValueOnce([
          { direction: 'in', _sum: { amount: { toNumber: () => 1000 } } },
        ])
        .mockResolvedValueOnce([]);

      const result = await service.getCustodianBalance(custodianId, companyId);

      expect(result.totalIn).toBe(1000);
      expect(result.totalOut).toBe(0);
      expect(result.netBalance).toBe(1000);
    });

    it('should decrease balance for OUT movements', async () => {
      prisma.moneyMovement.groupBy
        .mockResolvedValueOnce([])
        .mockResolvedValueOnce([
          { direction: 'out', _sum: { amount: { toNumber: () => 400 } } },
        ]);

      const result = await service.getCustodianBalance(custodianId, companyId);

      expect(result.totalIn).toBe(0);
      expect(result.totalOut).toBe(400);
      expect(result.netBalance).toBe(-400);
    });

    it('should compute correct net balance with IN and OUT movements', async () => {
      prisma.moneyMovement.groupBy
        .mockResolvedValueOnce([
          { direction: 'in', _sum: { amount: { toNumber: () => 5000 } } },
        ])
        .mockResolvedValueOnce([
          { direction: 'out', _sum: { amount: { toNumber: () => 3200 } } },
        ]);

      const result = await service.getCustodianBalance(custodianId, companyId);

      expect(result.totalIn).toBe(5000);
      expect(result.totalOut).toBe(3200);
      expect(result.netBalance).toBe(1800);
    });

    it('should exclude superseded originals from balance', async () => {
      // Simulate one superseded row (id "orig-1" was edited)
      prisma.moneyMovement.findMany.mockResolvedValue([
        { editedFromId: 'orig-1' },
      ]);

      prisma.moneyMovement.groupBy
        .mockResolvedValueOnce([
          { direction: 'in', _sum: { amount: { toNumber: () => 2000 } } },
        ])
        .mockResolvedValueOnce([
          { direction: 'out', _sum: { amount: { toNumber: () => 500 } } },
        ]);

      const result = await service.getCustodianBalance(custodianId, companyId);

      // The groupBy queries exclude the superseded IDs, so only
      // the non-superseded rows contribute
      expect(result.netBalance).toBe(1500);

      // Verify that the groupBy was called with a notIn filter
      const inGroupByCall = prisma.moneyMovement.groupBy.mock.calls[0][0];
      expect(inGroupByCall.where.id.notIn).toEqual(['orig-1']);
    });

    it('should include confirmed custody transfers in balance', async () => {
      prisma.moneyMovement.groupBy
        .mockResolvedValueOnce([
          { direction: 'in', _sum: { amount: { toNumber: () => 1000 } } },
        ])
        .mockResolvedValueOnce([]);

      // Incoming confirmed transfer
      prisma.custodyTransfer.aggregate
        .mockResolvedValueOnce({
          _sum: { amount: { toNumber: () => 750 } },
        })
        // Outgoing confirmed transfer
        .mockResolvedValueOnce({
          _sum: { amount: { toNumber: () => 0 } },
        });

      const result = await service.getCustodianBalance(custodianId, companyId);

      expect(result.confirmedTransferIn).toBe(750);
      expect(result.confirmedTransferOut).toBe(0);
      expect(result.netBalance).toBe(1750);
    });

    it('should NOT include pending custody transfers in balance', async () => {
      prisma.moneyMovement.groupBy
        .mockResolvedValueOnce([
          { direction: 'in', _sum: { amount: { toNumber: () => 1000 } } },
        ])
        .mockResolvedValueOnce([]);

      // All transfers are null (not confirmed) → excluded from balance
      prisma.custodyTransfer.aggregate
        .mockResolvedValue({ _sum: { amount: null } });

      const result = await service.getCustodianBalance(custodianId, companyId);

      expect(result.confirmedTransferIn).toBe(0);
      expect(result.confirmedTransferOut).toBe(0);
      expect(result.netBalance).toBe(1000);
    });

    it('should NOT include disputed custody transfers in balance', async () => {
      prisma.moneyMovement.groupBy
        .mockResolvedValueOnce([
          { direction: 'in', _sum: { amount: { toNumber: () => 3000 } } },
        ])
        .mockResolvedValueOnce([]);

      // Only confirmed transfers are summed — disputed ones are excluded
      // by the `status: 'confirmed'` filter in the aggregate query.
      // So returning null means no confirmed transfers exist.
      prisma.custodyTransfer.aggregate
        .mockResolvedValue({ _sum: { amount: null } });

      const result = await service.getCustodianBalance(custodianId, companyId);

      expect(result.netBalance).toBe(3000);
    });
  });
});