import { SetMetadata } from '@nestjs/common';

export const ROLES_KEY = 'roles';

/**
 * Role hierarchy (highest → lowest):
 *   admin > approver > accounts > collector
 *
 * Use @Roles('accounts') on a handler to require that the calling user
 * has at least the "accounts" role (i.e. accounts, approver, or admin).
 */
export const ROLE_HIERARCHY: Record<string, number> = {
  admin: 4,
  approver: 3,
  accounts: 2,
  collector: 1,
};

/**
 * @Roles('accounts') — user must hold at least one of the listed roles
 * (or a higher role in the hierarchy).
 */
export const Roles = (...roles: string[]) => SetMetadata(ROLES_KEY, roles);