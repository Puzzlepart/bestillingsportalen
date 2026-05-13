require('@rushstack/eslint-config/patch/modern-module-resolution');

module.exports = {
  extends: ['@microsoft/eslint-config-spfx/lib/profiles/react'],
  parserOptions: { tsconfigRootDir: __dirname },
  overrides: [
    {
      files: ['*.ts', '*.tsx'],
      parser: '@typescript-eslint/parser',
      'parserOptions': {
        'project': './tsconfig.json',
        'ecmaVersion': 2018,
        'sourceType': 'module'
      },
      rules: {
        '@rushstack/hoist-jest-mock': 1,
        '@rushstack/import-requires-chunk-name': 1,
        '@rushstack/pair-react-dom-render-unmount': 1
      }
    }
  ]
};
