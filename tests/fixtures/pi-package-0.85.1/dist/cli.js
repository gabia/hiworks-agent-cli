#!/usr/bin/env node
// Deterministic CLI contract fixture; never a live interactive-agent test.
const command = process.argv[2];
if (command === '--version') console.log('0.85.1');
if (command === '--help') console.log('Usage: pi [options]\n  --help --version');
