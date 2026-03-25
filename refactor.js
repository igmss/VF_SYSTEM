const fs = require('fs');

const filePath = process.argv[2];
if (!filePath) {
    console.error('No file provided');
    process.exit(1);
}

let code = fs.readFileSync(filePath, 'utf-8');

// 1. Add import if completely missing
if (!code.includes('import \'../../theme/app_theme.dart\';')) {
    code = code.replace(
        /import 'package:flutter\/material.dart';\n/,
        `import 'package:flutter/material.dart';\nimport '../../theme/app_theme.dart';\n`
    );
}

// 2. Remove const keyword before widgets that use colors getting AppTheme reference
code = code.replace(/const\s+(TextStyle\([^)]*color:\s*Colors\.white[^)]*\))/g, '$1');
code = code.replace(/const\s+(Text\([^)]*style:\s*(?:const\s+)?TextStyle\([^)]*color:\s*Colors\.white[^)]*\))/g, '$1');
code = code.replace(/const\s+(Icon\([^)]*color:\s*Colors\.white[^)]*\))/g, '$1');
code = code.replace(/const\s+(IconThemeData\([^)]*color:\s*Colors\.white[^)]*\))/g, '$1');

// specific removal of const applied to parent blocks where white colors might be referenced
// It's hard to be perfect with JS regex, but this removes `const` from `const Text` and `const TextStyle` and `const Icon` and `const IconThemeData`.
code = code.replace(/const\s+(TextStyle\([^)]*color:\s*Colors\.black[^)]*\))/g, '$1');

// 3. Define substitutions
// Colors.white...
code = code.replace(/Colors\.white(?!10|12|24|38|54|60|70|\.with)/g, 'AppTheme.textPrimaryColor(context)');
code = code.replace(/Colors\.white54/g, 'AppTheme.textMutedColor(context)');
code = code.replace(/Colors\.white60/g, 'AppTheme.textMutedColor(context)');
code = code.replace(/Colors\.white38/g, 'AppTheme.textMutedColor(context)');
code = code.replace(/Colors\.white70/g, 'AppTheme.textPrimaryColor(context).withValues(alpha: 0.7)');
code = code.replace(/Colors\.white24/g, 'AppTheme.textMutedColor(context).withValues(alpha: 0.6)');
code = code.replace(/Colors\.white12/g, 'AppTheme.lineColor(context)');
code = code.replace(/Colors\.white10/g, 'AppTheme.lineColor(context)');
code = code.replace(/Colors\.white\.withOpacity\((.*?)\)/g, 'AppTheme.textPrimaryColor(context).withValues(alpha: $1)');

// Handle Surface color defaults mostly hardcoded like AppTheme.surfaceColor(context) vs _kSurface
// Not doing this generally unless they appear, but we focus on Colors.white

// Specific to collectors_screen and other dark backgrounds: 
code = code.replace(/const Color\(0xFF1E1E3A\)/g, 'AppTheme.surfaceColor(context)');
code = code.replace(/const Color\(0xFF16162A\)/g, 'AppTheme.surfaceColor(context)');
code = code.replace(/Color\(0xFF1E1E3A\)/g, 'AppTheme.surfaceColor(context)');
code = code.replace(/Color\(0xFF16162A\)/g, 'AppTheme.surfaceColor(context)');

// Remove bad trailing const that might get isolated
// We leave compiler errors if `const` ends up applying to a non-const constructor, dart analyze will find them.

fs.writeFileSync(filePath, code);
console.log('Processed', filePath);
