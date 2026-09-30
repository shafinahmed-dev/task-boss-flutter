import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';

export interface JwtPayload {
  sub: string;        // user ID
  role: string;       // admin | approver | accounts | collector
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
      role: payload.role,
      companyIds: payload.companyIds ?? [],
    };
  }
}