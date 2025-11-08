const router = require('express').Router();
const Student = require('../models/student');
const sequelize = require('../utils/database');
const metricsController = require('../../../metrics/metrics.controller');
const dbMetrics = require('../../../metrics/db.metrics');

// Test endpoint to trigger all alerts
router.get('/trigger-alerts', async (req, res) => {
  const { alertType } = req.query;
  
  try {
    switch (alertType) {
      case 'high-error-rate':
        // Trigger high HTTP error rate (> 0.1 errors/sec)
        // Return 500 errors for 6 minutes to exceed 0.1 errors/sec threshold
        res.status(500).json({ 
          error: 'Intentional error for alert testing',
          alert: 'HighHTTPErrorRate'
        });
        break;

      case 'high-latency':
        // Trigger high latency (p90 > 1s, p95 > 2s, p99 > 5s)
        const delay = parseInt(req.query.delay) || 6000; // 6 seconds default
        await new Promise(resolve => setTimeout(resolve, delay));
        res.status(200).json({ 
          message: 'High latency response',
          delay: delay,
          alert: 'HighLatency'
        });
        break;

      case 'database-error':
        // Trigger database errors (> 0.05 errors/sec)
        // Force a database error by using invalid SQL
        try {
          await sequelize.query('SELECT * FROM non_existent_table_xyz_123');
        } catch (dbError) {
          // Increment error counter
          dbMetrics.dbErrorCount.inc({
            operation: 'select',
            error_type: 'SequelizeDatabaseError',
            application: 'student-api'
          });
          res.status(500).json({ 
            error: 'Database error triggered',
            alert: 'DatabaseErrors'
          });
        }
        break;

      case 'high-db-connections':
        // Trigger high database connections (> 50)
        // Create multiple connections
        const connectionPromises = [];
        for (let i = 0; i < 60; i++) {
          connectionPromises.push(
            sequelize.query('SELECT 1').catch(() => {})
          );
        }
        await Promise.all(connectionPromises);
        res.status(200).json({ 
          message: 'High connection count triggered',
          alert: 'HighDatabaseConnections'
        });
        break;

      case 'slow-db-query':
        // Trigger slow database queries (p95 > 1s)
        const queryDelay = parseInt(req.query.delay) || 2000; // 2 seconds
        const startTime = Date.now();
        
        // Simulate slow query by doing a complex query or using pg_sleep if available
        try {
          // Try pg_sleep first (PostgreSQL)
          await sequelize.query(`SELECT pg_sleep(${queryDelay / 1000})`);
        } catch (pgError) {
          // If pg_sleep fails, simulate delay with a complex query
          await new Promise(resolve => setTimeout(resolve, queryDelay));
          // Execute a query that might be slow
          await Student.findAll({
            where: {},
            order: [['id', 'DESC']],
            limit: 1000
          });
        }
        
        const duration = (Date.now() - startTime) / 1000;
        
        // Manually record slow query
        dbMetrics.dbQueryDuration.observe({
          query_type: 'SELECT',
          table: 'Students',
          operation: 'select',
          application: 'student-api'
        }, duration);
        
        res.status(200).json({ 
          message: 'Slow query executed',
          duration: duration,
          alert: 'SlowDatabaseQueries'
        });
        break;

      case 'cpu-intensive':
        // Trigger high CPU usage (> 80%)
        const iterations = parseInt(req.query.iterations) || 100000000;
        let result = 0;
        for (let i = 0; i < iterations; i++) {
          result += Math.sqrt(i) * Math.random();
        }
        res.status(200).json({ 
          message: 'CPU intensive operation completed',
          result: result,
          alert: 'HighPodCPUUsage'
        });
        break;

      case 'cpu-continuous':
        // Continuously consume CPU to trigger alert (runs in background)
        const cpuDuration = parseInt(req.query.duration) || 600000; // 10 minutes default
        res.status(200).json({ 
          message: 'Starting continuous CPU load...',
          duration: cpuDuration,
          alert: 'HighPodCPUUsage'
        });
        // Run CPU-intensive loop in background
        setImmediate(() => {
          const endTime = Date.now() + cpuDuration;
          while (Date.now() < endTime) {
            Math.sqrt(Math.random() * 1000000);
          }
        });
        break;

      case 'memory-intensive':
        // Trigger high memory usage (> 85%)
        const arraySize = parseInt(req.query.size) || 10000000;
        const largeArray = new Array(arraySize).fill(0).map((_, i) => ({
          id: i,
          data: 'x'.repeat(1000),
          timestamp: Date.now()
        }));
        res.status(200).json({ 
          message: 'Memory intensive operation completed',
          arraySize: largeArray.length,
          alert: 'HighPodMemoryUsage'
        });
        break;

      case 'memory-leak':
        // Continuously allocate memory to cause OOM
        const leakSize = parseInt(req.query.size) || 50000000; // 50M per allocation
        const leakCount = parseInt(req.query.count) || 20; // 20 allocations = ~1GB
        const memoryLeak = [];
        
        res.status(200).json({ 
          message: 'Starting memory leak...',
          leakSize: leakSize,
          leakCount: leakCount,
          alert: 'HighPodMemoryUsage / OOM'
        });
        
        // Allocate memory and keep it referenced
        for (let i = 0; i < leakCount; i++) {
          memoryLeak.push(new Array(leakSize).fill('x'.repeat(100)));
          // Small delay to allow memory allocation
          await new Promise(resolve => setTimeout(resolve, 100));
        }
        
        // Keep memory allocated (don't let it be garbage collected)
        global.memoryLeak = memoryLeak;
        break;

      case 'oom':
        // Force Out of Memory by allocating massive amounts of memory
        res.status(200).json({ 
          message: 'Triggering OOM...',
          alert: 'OOMKilled'
        });
        
        // Allocate memory until OOM
        const oomArrays = [];
        try {
          while (true) {
            // Allocate 100MB at a time
            oomArrays.push(new Array(10000000).fill('x'.repeat(100)));
          }
        } catch (error) {
          console.error('OOM triggered:', error);
        }
        break;

      case 'crash':
        // Trigger pod crash (for testing CrashLoopBackOff)
        res.status(200).json({ 
          message: 'About to crash...',
          alert: 'PodCrashLoopBackOff'
        });
        // Exit process after a short delay to allow response
        setTimeout(() => {
          process.exit(1);
        }, 1000);
        break;

      case 'crash-loop':
        // Continuously crash the pod to trigger CrashLoopBackOff
        res.status(200).json({ 
          message: 'Starting crash loop...',
          alert: 'PodCrashLoopBackOff'
        });
        // Crash immediately
        process.exit(1);
        break;

      default:
        res.status(400).json({ 
          error: 'Invalid alert type',
          availableTypes: [
            'high-error-rate',
            'high-latency',
            'database-error',
            'high-db-connections',
            'slow-db-query',
            'cpu-intensive',
            'cpu-continuous',
            'memory-intensive',
            'memory-leak',
            'oom',
            'crash',
            'crash-loop'
          ]
        });
    }
  } catch (error) {
    console.error('Test endpoint error:', error);
    res.status(500).json({ 
      error: 'Test endpoint failed',
      message: error.message
    });
  }
});

// Endpoint to trigger multiple errors rapidly
router.get('/trigger-errors', async (req, res) => {
  const count = parseInt(req.query.count) || 10;
  const statusCode = parseInt(req.query.status) || 500;
  
  // This will be called multiple times to generate error rate
  res.status(statusCode).json({ 
    error: 'Intentional error',
    count: count
  });
});

// Endpoint to trigger multiple slow requests
router.get('/trigger-slow-requests', async (req, res) => {
  const delay = parseInt(req.query.delay) || 3000; // 3 seconds
  await new Promise(resolve => setTimeout(resolve, delay));
  res.status(200).json({ 
    message: 'Slow request completed',
    delay: delay
  });
});

module.exports = router;

