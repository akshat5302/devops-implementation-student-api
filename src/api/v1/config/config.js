require('dotenv').config();

module.exports = {
  development: {
    username: process.env.POSTGRES_USER || 'akshat',
    password: process.env.POSTGRES_PASSWORD || '12345',
    database: process.env.POSTGRES_DB || 'student_db',
    host: process.env.POSTGRES_HOST || 'node_db',
    dialect: 'postgres',
  },
  test: {
    username: process.env.POSTGRES_USER || 'akshat',
    password: process.env.POSTGRES_PASSWORD || '12345',
    database: process.env.POSTGRES_DB || 'student_db',
    host: process.env.POSTGRES_HOST || 'node_db',
    dialect: 'postgres',
  },
  production: {
    username: process.env.POSTGRES_USER || 'akshat',
    password: process.env.POSTGRES_PASSWORD || '12345',
    database: process.env.POSTGRES_DB || 'student_db',
    host: process.env.POSTGRES_HOST || 'student-crud-api-api-db',
    dialect: 'postgres',
  },
};
