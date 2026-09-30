import {
  Controller,
  Get,
  Post,
  Patch,
  Delete,
  Param,
  Body,
  Query,
  Req,
  HttpCode,
  HttpStatus,
  NotFoundException,
} from '@nestjs/common';
import { WalletService } from './wallet.service.js';
import type { CreateWalletDto, WalletTransferDto, UpdateWalletDto } from './wallet.service.js';
import { PrismaService } from '../../database/prisma.service.js';

@Controller('wallets')
export class WalletController {
  constructor(
    private readonly walletService: WalletService,
    private readonly prisma: PrismaService,
  ) {}

  @Get()
  async getWallets(
    @Query('custodianId') queryCustodianId?: string,
    @Req() req?: { user?: { id: string } },
  ) {
    let custodianId = queryCustodianId;
    if (!custodianId && req?.user?.id) {
      let custodian = await this.prisma.custodianAccount.findFirst({
        where: { linkedUserId: req.user.id },
      });
      if (!custodian) {
        const user = await this.prisma.user.findUnique({
          where: { id: req.user.id },
          include: { companies: true },
        });
        const companyId =
          user?.companies[0]?.companyId ||
          (await this.prisma.company.findFirst())?.id;
        if (companyId) {
          custodian = await this.prisma.custodianAccount.create({
            data: {
              name: `${user?.name || 'User'} Wallet / Cash`,
              type: 'person',
              companyId,
              linkedUserId: req.user.id,
            },
          });
        }
      }
      if (custodian) {
        custodianId = custodian.id;
      }
    }

    if (!custodianId) {
      throw new NotFoundException('custodianId is required or user must have linked custodian account');
    }

    return this.walletService.getWallets(custodianId);
  }

  @Post()
  @HttpCode(HttpStatus.CREATED)
  async createWallet(
    @Body() dto: CreateWalletDto,
    @Req() req: { user: { id: string } },
  ) {
    return this.walletService.createWallet(dto, req.user.id);
  }

  @Post('transfer')
  @HttpCode(HttpStatus.OK)
  async transfer(
    @Body() dto: WalletTransferDto,
    @Req() req: { user: { id: string } },
  ) {
    return this.walletService.transferBetweenWallets(dto, req.user.id);
  }

  @Patch(':id')
  @HttpCode(HttpStatus.OK)
  async updateWallet(
    @Param('id') id: string,
    @Body() dto: UpdateWalletDto,
    @Req() req: { user?: { id: string } },
  ) {
    return this.walletService.updateWallet(id, dto, req.user?.id);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  async deleteWallet(
    @Param('id') id: string,
    @Req() req: { user?: { id: string } },
  ) {
    return this.walletService.deleteWallet(id, req.user?.id);
  }
}