import { Module } from '@nestjs/common';
import { CategoryController } from './category.controller.js';
import { CategoryService } from './category.service.js';
import { DatabaseModule } from '../../database/database.module.js';

@Module({
  imports: [DatabaseModule],
  controllers: [CategoryController],
  providers: [CategoryService],
  exports: [CategoryService],
})
export class CategoryModule {}
