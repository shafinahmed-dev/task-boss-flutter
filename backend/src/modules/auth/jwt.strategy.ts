import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';

export interface JwtPayload {
  sub: string;        // user ID
  handle: string;     // user handle e.g. "suite.taskgroup"
  role: string;       // SUITE_ADMIN | MANAGER | EMPLOYEE | admin | approver | accounts | collector
  tenantId?: string;  // tenant UUID
  companyIds: string[]; // authorized company IDs
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor() {
    const jwtSecret = process.env.JWT_SECRET ?? 'task-bos-dev-secret';
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: jwtSecret,
    });
  }

  validate(payload: JwtPayload) {
    if (!payload.sub || !payload.role) {
      throw new UnauthorizedException('Invalid token payload');
    }
    // Attach user info to request object
    return {
      id: payload.sub,
      handle: payload.handle,
      role: payload.role,
      tenantId: payload.tenantId,
      companyIds: payload.companyIds ?? [],
    };
  }
}