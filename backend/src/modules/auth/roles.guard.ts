import {
  Injectable,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ROLES_KEY, ROLE_HIERARCHY } from './roles.decorator.js';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<string[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);

    // If no @Roles() decorator is present, allow access
    if (!requiredRoles || requiredRoles.length === 0) {
      return true;
    }

    const request = context.switchToHttp().getRequest();
    const user = request.user;

    if (!user || !user.role) {
      throw new ForbiddenException('No role information on request');
    }

    const userLevel = ROLE_HIERARCHY[user.role] ?? 0;

    // User passes if they have ANY of the required roles (via hierarchy)
    const allowed = requiredRoles.some((required) => {
      const requiredLevel = ROLE_HIERARCHY[required] ?? 0;
      return userLevel >= requiredLevel;
    });

    if (!allowed) {
      throw new ForbiddenException(
        `Role "${user.role}" is insufficient. Required: ${requiredRoles.join(' or ')}`,
      );
    }

    return true;
  }
}