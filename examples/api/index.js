import express from 'express';
import promMiddleware from 'express-prometheus-middleware';
import { trace, context } from "@opentelemetry/api";

import { logger } from './logger.js';
import './tracer.js';


const app = express();
const PORT = process.env.PORT || 9091;

// Middleware to add request logging with trace context
app.use((req, res, next) => {
  const span = trace.getActiveSpan();
  const traceId = span?.spanContext().traceId;
  const spanId = span?.spanContext().spanId;

  // Log incoming request with structured data
  logger.info('Incoming request', {
    method: req.method,
    path: req.path,
    query: req.query,
    trace_id: traceId,
    span_id: spanId,
    user_agent: req.get('user-agent'),
    ip: req.ip
  });

  // Log response when finished
  const startTime = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - startTime;
    logger.info('Request completed', {
      method: req.method,
      path: req.path,
      status: res.statusCode,
      duration_ms: duration,
      trace_id: traceId,
      span_id: spanId
    });
  });

  next();
});

app.use(promMiddleware({
  metricsPath: '/metrics',
  collectDefaultMetrics: true,
  requestDurationBuckets: [0.1, 0.5, 1, 1.5],
}));

// this creates custom spans to be sent to tempo
const tracer = trace.getTracer(process.env.TEMPO_SERVICE_NAME || 'unknown')

app.get('/hello', (req, res) => {
  const span = tracer.startSpan("parse json");
  const traceId = span?.spanContext().traceId;

  logger.info('Processing hello endpoint', {
    name: req.query.name || 'Anon',
    trace_id: traceId
  });

  const { name = 'Anon' } = req.query;
  res.json({ message: `Hello, ${name}!` });
  span.end();
});

// Error endpoint for testing error logging
app.get('/error', (req, res) => {
  const span = tracer.startSpan("error endpoint");
  const traceId = span?.spanContext().traceId;

  try {
    throw new Error('This is a test error');
  } catch (error) {
    logger.error('Error occurred in /error endpoint', {
      error: error.message,
      stack: error.stack,
      trace_id: traceId
    });
    res.status(500).json({ error: 'Internal server error' });
  } finally {
    span.end();
  }
});

// Slow endpoint for testing performance logging
app.get('/slow', async (req, res) => {
  const span = tracer.startSpan("slow endpoint");
  const traceId = span?.spanContext().traceId;

  const delay = parseInt(req.query.delay) || 1000;

  logger.warn('Slow endpoint called', {
    delay_ms: delay,
    trace_id: traceId
  });

  await new Promise(resolve => setTimeout(resolve, delay));

  res.json({ message: 'Slow response', delay });
  span.end();
});

app.listen(PORT, () => {
  logger.info('Server started', {
    port: PORT,
    environment: process.env.NODE_ENV || 'development'
  });
  console.log(`Example api is listening on http://localhost:${PORT}`);
});