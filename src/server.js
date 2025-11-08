const express = require('express');
const bodyparser = require('body-parser');
const sequelize = require('./api/v1/utils/database');
const Student = require('./api/v1/models/student');
const metricsController = require('./metrics/metrics.controller');
const metricsRoutes = require('./metrics/metrics.routes');
const dbMetrics = require('./metrics/db.metrics');

const app = express();

dbMetrics.setupSequelizeHooks(sequelize);
app.use(metricsController.trackMetrics());

// CORS middleware - must be before body parser
app.use((req, res, next) => {
  // Set CORS headers for all requests
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, Accept, X-Requested-With');
  res.setHeader('Access-Control-Allow-Credentials', 'true');
  
  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }
  
  next();
});

app.use(bodyparser.json());
app.use(bodyparser.urlencoded({ extended: false }));

app.get('/', (req, res, next) => {
  res.send('Hello World using Gitops and ArgoCD with Argo Workflows');
});

app.use('/api/v1/health', require('./api/v1/routes/healthroute'));
app.use('/api/v1/students', require('./api/v1/routes/studentsroute'));
app.use('/api/v1/test', require('./api/v1/routes/testroute'));
app.use('/metrics', metricsRoutes);

app.use((error, req, res, next) => {
  console.log(error);
  const status = error.statusCode || 500;
  const { message } = error;
  res.status(status).json({ message });
});

// Export the app for testing
module.exports = app;

// Only start the server if this file is run directly
if (require.main === module) {
  sequelize
    .sync()
    .then((result) => {
      console.log('Database connected');
      app.listen(3000, () => {
        console.log('Server is running on port 3000');
        console.log('Metrics available at http://localhost:3000/metrics');
      });
    })
    .catch((err) => console.log(err));
}