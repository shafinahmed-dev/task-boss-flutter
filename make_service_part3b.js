const fs = require('fs');
const part3b = `
  async deleteCategory(reqUser: any, id: string) {
    const category = await this.prisma.transactionCategory.findUnique({
      where: { id },
    });
    if (!category) {
      throw new NotFoundException('Category not found');
    }
    if (category.tenantId !== reqUser.tenantId || !['MANAGER', 'SUITE_ADMIN'].includes(reqUser.role)) {
      throw new ForbiddenException('Unauthorized');
    }

    const movementsCount = await this.prisma.moneyMovement.count({
      where: { categoryId: id },
    });

    if (movementsCount > 0) {
      throw new BadRequestException('Cannot delete category because it has associated transactions.');
    }

    await this.prisma.transactionCategory.delete({
      where: { id },
    });

    return { success: true };
  }
}
`;
fs.appendFileSync('backend/src/modules/category/category.service.ts', part3b);
