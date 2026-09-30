import { CustodyService } from './custody.service.js';
import { PrismaService } from '../../database/prisma.service.js';

function createMockPrisma() {
  return {
    custodianAccount: {
      findUnique: vi.fn(),
      findFirst: vi.fn(),
      findMany: vi.fn(),
      count: vi.fn(),
      create: vi.fn(),
    },
    custodyTransfer: {
      findUnique: vi.fn(),
      findMany: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
    },
    wallet: {
      findUnique: vi.fn(),
      findFirst: vi.fn(),
      findMany: vi.fn(),
      create: vi.fn(),
    },
    moneyMovement: {
      findMany: vi.fn(),
      create: vi.fn(),
    },
    user: {
      findFirst: vi.fn(),
      create: vi.fn(),
    },
    userCompany: {
      findUnique: vi.fn(),
      create: vi.fn(),
    },
    company: {
      findFirst: vi.fn(),
    },
    $transaction: vi.fn(),
  } as unknown as PrismaService;
}

describe('CustodyService', () => {
  let service: CustodyService;
  let prisma: ReturnType<typeof createMockPrisma>;

  beforeEach(() => {
    prisma = createMockPrisma();
    service = new CustodyService(prisma as any);
  });

  describe('getCustodians', () => {
    it('should return mapped custodians with linked user designation and department', async () => {
      const companyId = 'a1111111-1111-1111-1111-111111111111';
      (prisma.custodianAccount.count as any).mockResolvedValue(3);
      (prisma.custodianAccount.findMany as any).mockResolvedValue([
        {
          id: 'cust-1',
          name: 'Fallback Name',
          type: 'person',
          companyId,
          linkedUser: {
            id: 'u-1',
            name: 'Rafiqul Islam',
            role: 'collector',
            designation: 'Site Engineer',
            department: 'Engineering',
          },
        },
      ]);

      const result = await service.getCustodians(companyId);

      expect(result).toHaveLength(1);
      expect(result[0]).toEqual({
        id: 'cust-1',
        name: 'Rafiqul Islam',
        designation: 'Site Engineer',
        department: 'Engineering',
        type: 'person',
        companyId,
        linkedUser: {
          id: 'u-1',
          name: 'Rafiqul Islam',
          role: 'collector',
          designation: 'Site Engineer',
          department: 'Engineering',
        },
      });
    });

    it('should fallback to first company if invalid/no companyId provided', async () => {
      const companyId = 'a1111111-1111-1111-1111-111111111111';
      (prisma.company.findFirst as any).mockResolvedValue({ id: companyId, name: 'Task Ltd' });
      (prisma.custodianAccount.count as any).mockResolvedValue(3);
      (prisma.custodianAccount.findMany as any).mockResolvedValue([]);

      const result = await service.getCustodians(undefined);

      expect(prisma.company.findFirst).toHaveBeenCalled();
      expect(result).toEqual([]);
    });
  });
});
