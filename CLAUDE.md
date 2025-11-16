# CLAUDE.md - ClickHouseDataMocker

This document provides essential information for AI assistants working on the ClickHouseDataMocker project. It contains project context, coding conventions, and development workflows.

## Project Overview

ClickHouseDataMocker is a tool for generating realistic mock/test data compatible with ClickHouse columnar database. The project aims to provide developers with utilities for:

- Generating synthetic datasets that respect ClickHouse data types
- Creating realistic test data for development and testing environments
- Supporting various ClickHouse-specific data types (DateTime64, LowCardinality, Nested, etc.)
- Bulk data generation with configurable schemas

## Recommended Project Structure

```
ClickHouseDataMocker/
├── src/                      # Source code
│   ├── generators/           # Data generators for different types
│   │   ├── numeric.ts        # Int8, Int16, UInt32, Float64, Decimal, etc.
│   │   ├── string.ts         # String, FixedString, UUID
│   │   ├── datetime.ts       # Date, DateTime, DateTime64
│   │   ├── complex.ts        # Array, Tuple, Map, Nested, JSON
│   │   └── index.ts          # Generator registry
│   ├── schema/               # Schema parsing and validation
│   │   ├── parser.ts         # Parse ClickHouse CREATE TABLE statements
│   │   └── types.ts          # TypeScript type definitions
│   ├── output/               # Output formatters
│   │   ├── csv.ts            # CSV format
│   │   ├── json.ts           # JSON/JSONEachRow format
│   │   └── native.ts         # ClickHouse native format
│   ├── cli/                  # Command-line interface
│   │   └── index.ts          # CLI entry point
│   └── index.ts              # Library entry point
├── tests/                    # Test files
│   ├── unit/                 # Unit tests
│   ├── integration/          # Integration tests
│   └── fixtures/             # Test fixtures and sample schemas
├── examples/                 # Example usage and schemas
├── docs/                     # Additional documentation
├── package.json              # Node.js package configuration
├── tsconfig.json             # TypeScript configuration
├── .eslintrc.json            # ESLint configuration
├── .prettierrc               # Prettier configuration
├── jest.config.js            # Jest test configuration
└── README.md                 # Project readme
```

## Technology Stack

### Recommended Stack
- **Language**: TypeScript 5.x
- **Runtime**: Node.js 20.x LTS or higher
- **Package Manager**: npm or pnpm
- **Testing**: Jest with ts-jest
- **Linting**: ESLint with TypeScript plugin
- **Formatting**: Prettier
- **Build**: tsc (TypeScript compiler) or esbuild

## ClickHouse Data Types Support

### Priority 1 - Core Types
- **Numeric**: Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64, Float32, Float64
- **Decimal**: Decimal(P, S), Decimal32, Decimal64, Decimal128
- **String**: String, FixedString(N)
- **Date/Time**: Date, Date32, DateTime, DateTime64(precision)
- **Boolean**: Bool
- **UUID**: UUID

### Priority 2 - Advanced Types
- **LowCardinality**: LowCardinality(Type)
- **Nullable**: Nullable(Type)
- **Array**: Array(Type)
- **Tuple**: Tuple(Type1, Type2, ...)
- **Map**: Map(KeyType, ValueType)
- **Enum**: Enum8, Enum16

### Priority 3 - Complex Types
- **Nested**: Nested structures
- **JSON**: New JSON data type (ClickHouse 2025)
- **Geo**: Point, Ring, Polygon, MultiPolygon
- **IPv4/IPv6**: IP address types

## Coding Conventions

### TypeScript Guidelines

```typescript
// Use explicit types for function parameters and return values
function generateInt32(min: number = -2147483648, max: number = 2147483647): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

// Use interfaces for data structures
interface ColumnDefinition {
  name: string;
  type: ClickHouseType;
  nullable: boolean;
  defaultValue?: unknown;
}

// Use type guards for runtime type checking
function isNumericType(type: ClickHouseType): type is NumericType {
  return ['Int8', 'Int16', 'Int32', 'Int64', 'UInt8', 'UInt16', 'UInt32', 'UInt64', 'Float32', 'Float64'].includes(type);
}

// Prefer const assertions for literal types
const SUPPORTED_FORMATS = ['csv', 'json', 'tsv', 'native'] as const;
type OutputFormat = typeof SUPPORTED_FORMATS[number];
```

### Naming Conventions
- **Files**: kebab-case (e.g., `datetime-generator.ts`)
- **Classes**: PascalCase (e.g., `DataGenerator`)
- **Functions/Methods**: camelCase (e.g., `generateRow`)
- **Constants**: SCREAMING_SNAKE_CASE (e.g., `MAX_BATCH_SIZE`)
- **Interfaces/Types**: PascalCase with descriptive names (e.g., `ColumnDefinition`)

### Code Organization
- One class/major export per file
- Group related functionality in subdirectories
- Keep files under 300 lines; refactor if larger
- Export types from a central `types.ts` file in each module

### Error Handling

```typescript
// Use custom error classes for domain-specific errors
class SchemaParseError extends Error {
  constructor(message: string, public line?: number) {
    super(message);
    this.name = 'SchemaParseError';
  }
}

// Always validate inputs
function generateFixedString(length: number): string {
  if (length <= 0 || length > 1000000) {
    throw new RangeError(`FixedString length must be between 1 and 1000000, got ${length}`);
  }
  // ... implementation
}
```

## Development Workflow

### Setup Commands
```bash
# Install dependencies
npm install

# Build the project
npm run build

# Run tests
npm test

# Run tests in watch mode
npm run test:watch

# Lint code
npm run lint

# Format code
npm run format

# Type check
npm run typecheck
```

### Git Workflow
1. Create feature branches from `main`
2. Use conventional commits:
   - `feat:` new features
   - `fix:` bug fixes
   - `docs:` documentation changes
   - `test:` adding tests
   - `refactor:` code refactoring
   - `chore:` maintenance tasks
3. Write descriptive commit messages explaining "why" not just "what"
4. Keep PRs focused and reasonably sized

### Testing Requirements
- Unit tests for all generators
- Test edge cases (min/max values, empty strings, special characters)
- Test ClickHouse-specific constraints (e.g., Date range [1970-01-01, 2149-06-06])
- Integration tests for schema parsing
- Aim for >80% code coverage

## Key Implementation Considerations

### Performance
- Support streaming for large datasets (avoid loading all data into memory)
- Use batch generation (configurable batch sizes, default 10,000 rows)
- Consider using worker threads for parallel generation
- Optimize random number generation for performance

### Data Realism
- Support for correlated data (e.g., start_date < end_date)
- Configurable data distributions (uniform, normal, weighted)
- Support for unique constraints
- Locale-aware string generation (names, addresses)

### ClickHouse Compatibility
- Respect data type boundaries (e.g., UInt8: 0-255)
- Handle timezone-aware DateTime generation
- Support ClickHouse-specific NULL semantics
- Generate valid values for Enum types

### CLI Interface Design
```bash
# Example CLI usage patterns to support
clickhouse-mock generate --schema schema.sql --rows 1000000 --format csv
clickhouse-mock generate --table "CREATE TABLE test (id UInt32, name String)" --rows 100
clickhouse-mock validate --schema schema.sql
clickhouse-mock types --list
```

## Security Considerations

- Never generate real PII (use clearly fake data)
- Sanitize user inputs when parsing schemas
- Avoid command injection in CLI
- Do not expose sensitive file paths in error messages

## API Design Principles

```typescript
// Fluent API for configuration
const generator = new DataMocker()
  .schema(tableSchema)
  .rows(100000)
  .batchSize(10000)
  .format('csv')
  .seed(12345);  // Reproducible generation

// Async iteration for streaming
for await (const batch of generator.stream()) {
  await writeToDisk(batch);
}
```

## Dependencies to Consider

### Production
- `@faker-js/faker` - Realistic fake data generation
- `yargs` or `commander` - CLI argument parsing
- `csv-stringify` - CSV generation
- `zod` - Runtime type validation

### Development
- `typescript` - TypeScript compiler
- `jest` - Testing framework
- `ts-jest` - TypeScript Jest transformer
- `eslint` - Linting
- `prettier` - Code formatting
- `@types/node` - Node.js type definitions

## Common Pitfalls to Avoid

1. **Integer Overflow**: Use BigInt for Int64/UInt64 types
2. **Floating Point Precision**: Use Decimal.js for Decimal types
3. **Date Range Violations**: ClickHouse Date is limited to [1970-01-01, 2149-06-06]
4. **String Encoding**: Ensure UTF-8 encoding for String types
5. **FixedString Padding**: Must be exactly N bytes, pad with null bytes
6. **Enum Validation**: Only generate declared enum values
7. **Nullable Handling**: Properly represent NULL vs empty values

## Future Enhancements

- Web UI for schema design and data preview
- ClickHouse connection for direct data insertion
- Schema inference from existing tables
- Data profiling to match production patterns
- Custom generator plugins
- Internationalization support

## Questions for Maintainers

When working on this project, consider:
1. What's the primary use case (testing, demos, benchmarking)?
2. Should we support direct ClickHouse insertion or only file output?
3. What's the expected scale (thousands vs billions of rows)?
4. Are there specific compliance requirements (GDPR, HIPAA)?

---

*Last updated: 2025-11-16*
*Project Status: Initial Setup*
