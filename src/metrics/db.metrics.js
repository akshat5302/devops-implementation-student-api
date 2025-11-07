const promClient = require('prom-client');
const metricsController = require('./metrics.controller');

class DatabaseMetrics {
    constructor() {
        this.initializeMetrics();
    }

    initializeMetrics() {
        this.dbQueryDuration = new promClient.Histogram({
            name: 'db_query_duration_seconds',
            help: 'Duration of database queries in seconds',
            labelNames: ['query_type', 'table', 'operation', 'application'],
            buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5, 7, 10],
            registers: [metricsController.register]
        });

        this.dbConnectionCount = new promClient.Gauge({
            name: 'db_connection_count',
            help: 'Number of active database connections',
            labelNames: ['application'],
            registers: [metricsController.register]
        });

        this.dbErrorCount = new promClient.Counter({
            name: 'db_error_total',
            help: 'Total number of database errors',
            labelNames: ['operation', 'error_type', 'application'],
            registers: [metricsController.register]
        });

        this.dbQueryCount = new promClient.Counter({
            name: 'db_query_total',
            help: 'Total number of database queries',
            labelNames: ['query_type', 'table', 'application'],
            registers: [metricsController.register]
        });
    }

    setupSequelizeHooks(sequelize) {
        if (!sequelize) {
            console.error('Sequelize instance not provided');
            return;
        }

        // Query lifecycle hooks
        const hookOptions = {
            beforeQuery: async (options) => {
                options.queryStartTime = Date.now();
                const queryType = options.type || 'unknown';
                const table = (options.model && options.model.name) || 'unknown';
                
                this.dbQueryCount.inc({
                    query_type: queryType,
                    table: table,
                    application: 'student-api'
                });
            },

            afterQuery: async (options) => {
                if (options.queryStartTime) {
                    const duration = (Date.now() - options.queryStartTime) / 1000;
                    const queryType = options.type || 'unknown';
                    const table = (options.model && options.model.name) || 'unknown';
                    const operation = this.getOperationType(options);

                    this.dbQueryDuration.observe({
                        query_type: queryType,
                        table: table,
                        operation: operation,
                        application: 'student-api'
                    }, duration);
                }
            }
        };

        // Register hooks
        Object.entries(hookOptions).forEach(([hookType, hookFunction]) => {
            if (typeof sequelize.options !== 'object') {
                sequelize.options = {};
            }
            if (typeof sequelize.options.hooks !== 'object') {
                sequelize.options.hooks = {};
            }
            sequelize.options.hooks[hookType] = hookFunction;
        });

        // Set up connection monitoring via periodic check
        setInterval(() => {
            if (sequelize.connectionManager && sequelize.connectionManager.pool) {
                try {
                    const totalConnections = sequelize.connectionManager.pool.totalCount;
                    const idleConnections = sequelize.connectionManager.pool.idleCount;
                    const activeConnections = totalConnections - idleConnections;
                    
                    this.dbConnectionCount.set({ application: 'student-api' }, activeConnections);
                } catch (error) {
                    console.error('Error updating connection metrics:', error);
                }
            }
        }, 5000); // Check every 5 seconds

        // Global error handler for Sequelize errors
        process.on('unhandledRejection', (error) => {
            if (error.name && error.name.includes('Sequelize')) {
                this.dbErrorCount.inc({
                    operation: this.getOperationType(error) || 'unknown',
                    error_type: error.name || 'unknown',
                    application: 'student-api'
                });
            }
        });

        console.log('Database metrics hooks configured');
    }

    getOperationType(options) {
        if (!options) return 'unknown';
        
        if (options.type) {
            return options.type.toLowerCase();
        }
        
        if (options.sql) {
            const sql = options.sql.toLowerCase();
            if (sql.startsWith('select')) return 'select';
            if (sql.startsWith('insert')) return 'insert';
            if (sql.startsWith('update')) return 'update';
            if (sql.startsWith('delete')) return 'delete';
        }
        
        return 'unknown';
    }
}

module.exports = new DatabaseMetrics();