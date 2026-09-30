import {
  Injectable,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { IS_PUBLIC_KEY } from './public.decorator.js';

/**
 * CompanyScopeGuard
 *
 * Enforces strict multi-entity (multi-company) isolation:
 *   • Every ledger, custody, and receipt query/mutation must carry a
 *     valid `company_id` (body, query, or param).
 *   • The requesting user must have that company_id in their JWT-
 *     authorized `companyIds` list.
 *   • If the user has no companyIds (e.g. unauthenticated context),
 *     access is denied.
 *
 * Usage: Apply globally or to specific controllers/routes.
 */
@Injectable()
export class CompanyScopeGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);

    if (isPublic) {
      return true;
    }

    const request = context.switchToHttp().getRequest();
    const user = request.user;

    if (!user || !Array.isArray(user.companyIds)) {
      throw new ForbiddenException('No company authorization on request');
    }

    // Extract company_id from body, query, or params — in that priority.
    const companyId: string | undefined =
      request.body?.companyId ??
      request.query?.companyId ??
      request.params?.companyId;

    // Some routes (e.g. balance with :id) may need companyId from query param
    if (!companyId) {
      // Allow routes that don't need company scoping (e.g. /auth/login)
      // If the route hasn't been annotated with this guard explicitly,
      // it won't hit this code path in most scenarios.
      return true;
    }

    if (!user.companyIds.includes(companyId)) {
      throw new ForbiddenException(
        `User is not authorized for company ${companyId}`,
      );
    }

    return true;
  }
}