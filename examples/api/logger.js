import { createLogger, transports, format } from 'winston';
import LokiTransport from 'winston-loki';

const LOKI_URL = process.env.LOKI_URL || 'http://loki:3100';

// JSON structured logging format
const jsonFormat = format.combine(
  format.timestamp({ format: 'YYYY-MM-DDTHH:mm:ss.SSSZ' }),
  format.errors({ stack: true }),
  format.json()
);

// Console format with colors for development
const consoleFormat = format.combine(
  format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
  format.colorize(),
  format.printf(({ timestamp, level, message, ...meta }) => {
    const metaStr = Object.keys(meta).length ? JSON.stringify(meta, null, 2) : '';
    return `${timestamp} ${level}: ${message} ${metaStr}`;
  })
);

const options = {
  format: jsonFormat,
  defaultMeta: {
    service: 'example-api',
    environment: process.env.NODE_ENV || 'development'
  },
  transports: [
    new LokiTransport({
      host: LOKI_URL,
      labels: {
        app: 'example-api',
        environment: process.env.NODE_ENV || 'development'
      },
      format: jsonFormat,
      json: true
    }),
    new transports.Console({
      format: consoleFormat
    })
  ],
};

export const logger = createLogger(options);