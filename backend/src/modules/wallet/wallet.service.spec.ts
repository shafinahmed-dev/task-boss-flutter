import { describe, it, expect, beforeEach, vi } from 'vitest';
import { WalletService } from './wallet.service.js';
import { PrismaService } from '../../database/prisma.service.js';
import { WalletType } from '@prisma/client';

function createMockPrisma() {
  return {
    wallet: {
      findUnique: vi.fn(),
      findFirst: vi.fn(),
      findMany: vi.fn(),
      create: vi.fn(),
      update: vi.fn(),
      updateMany: vi.fn(),
      delete: vi.fn(),
    },
    custodianAccount: {
      findUnique: vi.fn(),
      findFirst: vi.fn(),
    },
    moneyMovement: {
      findMany: vi.fn(),
      create: vi.fn(),
      count: vi.fn(),
    },
    $transaction: vi.fn(),
  } as unknown as PrismaService;
}

describe('WalletService', () => {
  let service: WalletService;
  let prisma: ReturnType<typeof createMockPrisma>;

  beforeEach(() => {
    prisma = createMockPrisma();
    service = new WalletService(prisma as any);
  });

  describe('getWallets', () => {
    it('should auto-provision a default Cash in Hand wallet when custodian has 0 wallets', async () => {
      const custodianId = 'c1111111-1111-1111-1111-111111111111';
      const companyId = 'a1111111-1111-1111-1111-111111111111';

      // 1. Initial findMany returns empty array
      (prisma.wallet.findMany as any).mockResolvedValueOnce([]);
      // 2. Custodian lookup
      (prisma.custodianAccount.findUnique as any).mockResolvedValue({
        id: custodianId,
        companyId,
      });
      // 3. Auto-created default wallet
      const mockCreatedWallet = {
        id: 'w-1',
        custodianId,
        companyId,
        name: 'Cash in Hand',
        type: WalletType.CASH,
        isDefault: true,
        isArchived: false,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
      (prisma.wallet.create as any).mockResolvedValue(mockCreatedWallet);

      // 4. moneyMovement lookups for superseded and balance
      (prisma.moneyMovement.findMany as any)
        .mockResolvedValueOnce([]) // superseded rows
        .mockResolvedValueOnce([]); // wallet movements

      const result = await service.getWallets(custodianId);

      expect(prisma.wallet.create).toHaveBeenCalledWith({
        data: {
          custodianId,
          companyId,
          name: 'Cash in Hand',
          type: WalletType.CASH,
          isDefault: true,
        },
      });
      expect(result).toHaveLength(1);
      expect(result[0].name).toBe('Cash in Hand');
      expect(result[0].currentBalance).toBe(0);
    });

    it('should compute balance properly for existing wallets', async () => {
      const custodianId = 'c1111111-1111-1111-1111-111111111111';
      const companyId = 'a1111111-1111-1111-1111-111111111111';

      const existingWallet = {
        id: 'w-1',
        custodianId,
        companyId,
        name: 'Cash in Hand',
        type: WalletType.CASH,
        isDefault: true,
        isArchived: false,
        createdAt: new Date(),
        updatedAt: new Date(),
      };
      (prisma.wallet.findMany as any).mockResolvedValueOnce([existingWallet]);
      (prisma.moneyMovement.findMany as any)
        .mockResolvedValueOnce([]) // superseded rows
        .mockResolvedValueOnce([
          { direction: 'in', amount: 5000, fee: 0 },
          { direction: 'out', amount: 1500, fee: 50 },
        ]);

      const result = await service.getWallets(custodianId);

      expect(prisma.wallet.create).not.toHaveBeenCalled();
      expect(result).toHaveLength(1);
      expect(result[0].currentBalance).toBe(3450);
    });
  });
});
