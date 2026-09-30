import {
  Controller,
  Post,
  Body,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ReceiptService } from './receipt.service.js';
import type { AssignBlockDto, IssueReceiptDto } from './receipt.service.js';

@Controller('receipts')
export class ReceiptController {
  constructor(private readonly receiptService: ReceiptService) {}

  /**
   * POST /receipts/blocks/assign
   * Admin assigns a numbered receipt block to a collector.
   */
  @Post('blocks/assign')
  @HttpCode(HttpStatus.CREATED)
  async assignBlock(@Body() dto: AssignBlockDto) {
    return this.receiptService.assignBlock(dto);
  }

  /**
   * POST /receipts/issue
   * Auto-increments pointer and issues a DigitalReceipt.
   */
  @Post('issue')
  @HttpCode(HttpStatus.CREATED)
  async issueReceipt(@Body() dto: IssueReceiptDto) {
    return this.receiptService.issueReceipt(dto);
  }
}