#!/usr/bin/env node

/**
 * Script to generate config.js from environment variable
 * Usage: REACT_APP_API_URL=http://localhost:3000/api/v1 node generate-config.js
 * Or: API_BASE_URL=http://localhost:3000/api/v1 node generate-config.js
 */

const fs = require('fs');
const path = require('path');

// Read from environment variable (supports both REACT_APP_API_URL and API_BASE_URL)
const apiUrl = process.env.REACT_APP_API_URL || process.env.API_BASE_URL || 'http://localhost:3000/api/v1';

const configContent = `// API Configuration
// This file is auto-generated from environment variable
// Set REACT_APP_API_URL or API_BASE_URL environment variable to change the API URL

window.API_BASE_URL = '${apiUrl}';
`;

const configPath = path.join(__dirname, 'config.js');

fs.writeFileSync(configPath, configContent, 'utf8');
console.log(`✅ Generated config.js with API URL: ${apiUrl}`);
console.log(`   File location: ${configPath}`);

