// ================================================================
// ESLint Configuration for KuberBank API
// ================================================================

module.exports = {
  env: {
    node: true,
    es2021: true,
    jest: true,
  },
  extends: [
    'airbnb-base',
    'plugin:jest/recommended',
  ],
  plugins: [
    'jest',
  ],
  parserOptions: {
    ecmaVersion: 'latest',
    sourceType: 'module',
  },
  rules: {
    // Console statements are allowed (for logging)
    'no-console': 'off',
    
    // Allow console in development
    'no-restricted-syntax': [
      'error',
      {
        selector: 'CallExpression[callee.object.name=\'console\'][callee.property.name!=/^(log|warn|error|info|trace)$/]',
        message: 'Unexpected property on console object was called',
      },
    ],
    
    // Underscore dangle for database fields
    'no-underscore-dangle': 'off',
    
    // Allow param reassignment (common in Express middleware)
    'no-param-reassign': ['error', { props: false }],
    
    // Consistent return not required (Express handlers)
    'consistent-return': 'off',
    
    // Allow unnamed functions in callbacks
    'func-names': 'off',
    
    // Prefer destructuring
    'prefer-destructuring': ['error', {
      array: false,
      object: true,
    }],
    
    // Max line length
    'max-len': ['error', {
      code: 120,
      ignoreComments: true,
      ignoreStrings: true,
      ignoreTemplateLiterals: true,
    }],
    
    // Allow single export
    'import/prefer-default-export': 'off',
    
    // Allow dev dependencies in tests
    'import/no-extraneous-dependencies': ['error', {
      devDependencies: [
        '**/__tests__/**',
        '**/*.test.js',
        '**/*.spec.js',
        '**/jest.*.js',
      ],
    }],
    
    // Require error handling in async
    'promise/catch-or-return': 'off',
    
    // Jest specific rules
    'jest/expect-expect': 'warn',
    'jest/no-disabled-tests': 'warn',
    'jest/no-focused-tests': 'error',
    'jest/no-identical-title': 'error',
    'jest/valid-expect': 'error',
  },
  overrides: [
    {
      files: ['**/__tests__/**', '**/*.test.js', '**/*.spec.js'],
      env: {
        jest: true,
      },
      rules: {
        // More lenient rules for tests
        'no-unused-expressions': 'off',
        'max-len': 'off',
        'global-require': 'off',
      },
    },
  ],
};