// Backend API Server Entry Point
import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';

// Load environment variables
dotenv.config();

const app = express();
const PORT = process.env.PORT || 3001;

// Middleware
app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Basic API route
app.get('/api', (req, res) => {
  res.json({ message: 'EduTech ChatBot API', version: '2.0.0' });
});

// Start server
app.listen(PORT, () => {
  console.log(`API Server running on port ${PORT}`);
});