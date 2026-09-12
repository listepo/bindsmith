#!/usr/bin/env node
// bindsmith TypeScript sidecar.
//
// Reads `.d.ts` files with the TypeScript Compiler API and prints a JSON model
// of every exported declaration. It is deliberately syntactic and faithful:
// no mapping to Dart happens here (that lives in the Dart `dts` driver where it
// is unit-tested), and every construct the model cannot express is emitted as
// `{ k: "unsupported", text }` so the driver can attach a marker.
//
// Usage: node index.mjs [--pretty] <file.d.ts> [...more]

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';

const MODEL_VERSION = 1;

/** @param {string[]} files @param {{cwd?: string}} [options] */
export function extract(files, { cwd = process.cwd() } = {}) {
  const roots = files.map((f) => path.resolve(cwd, f));
  const program = ts.createProgram(roots, {
    noEmit: true,
    skipLibCheck: true,
    target: ts.ScriptTarget.ES2022,
    module: ts.ModuleKind.NodeNext,
    moduleResolution: ts.ModuleResolutionKind.NodeNext,
    types: [],
  });
  const checker = program.getTypeChecker();
  const decls = [];
  for (const root of roots) {
    const sourceFile = program.getSourceFile(root);
    if (!sourceFile) throw new Error(`cannot load ${root}`);
    const ctx = { checker, decls, file: path.relative(cwd, root) };
    const moduleSymbol = checker.getSymbolAtLocation(sourceFile);
    if (moduleSymbol) {
      visitModuleExports(moduleSymbol, '', ctx);
    } else {
      for (const statement of sourceFile.statements) visitStatement(statement, '', ctx);
    }
  }
  return { version: MODEL_VERSION, typescript: ts.version, decls };
}

function visitModuleExports(moduleSymbol, ns, ctx) {
  for (const exported of ctx.checker.getExportsOfModule(moduleSymbol)) {
    const symbol = exported.flags & ts.SymbolFlags.Alias
      ? ctx.checker.getAliasedSymbol(exported)
      : exported;
    if (symbol.flags & ts.SymbolFlags.Module) {
      visitModuleExports(symbol, `${ns}${exported.name}.`, ctx);
      continue;
    }
    for (const declaration of symbol.declarations ?? []) {
      visitStatement(declaration, ns, ctx, exported.name);
    }
  }
}

function visitStatement(node, ns, ctx, exportedName) {
  if (ts.isClassDeclaration(node) || ts.isInterfaceDeclaration(node)) {
    ctx.decls.push({
      kind: ts.isClassDeclaration(node) ? 'class' : 'interface',
      name: ns + (exportedName ?? node.name?.text ?? 'default'),
      typeParams: typeParams(node),
      extends: heritage(node, ts.SyntaxKind.ExtendsKeyword),
      implements: heritage(node, ts.SyntaxKind.ImplementsKeyword),
      members: node.members.map((m) => member(m, ctx)).filter(Boolean),
      ...docs(node),
      ...loc(node, ctx),
    });
  } else if (ts.isFunctionDeclaration(node)) {
    ctx.decls.push({
      kind: 'function',
      name: ns + (exportedName ?? node.name?.text ?? 'default'),
      typeParams: typeParams(node),
      params: node.parameters.map(param),
      returns: type(node.type),
      ...docs(node),
      ...loc(node, ctx),
    });
  } else if (ts.isVariableStatement(node)) {
    for (const declaration of node.declarationList.declarations) {
      visitStatement(declaration, ns, ctx, exportedName);
    }
  } else if (ts.isVariableDeclaration(node)) {
    ctx.decls.push({
      kind: 'variable',
      name: ns + (exportedName ?? node.name.getText()),
      type: type(node.type),
      isConst: (ts.getCombinedNodeFlags(node) & ts.NodeFlags.Const) !== 0,
      ...docs(node.parent?.parent ?? node),
      ...loc(node, ctx),
    });
  } else if (ts.isEnumDeclaration(node)) {
    ctx.decls.push({
      kind: 'enum',
      name: ns + (exportedName ?? node.name.text),
      members: node.members.map((m) => ({
        name: propertyName(m.name),
        value: m.initializer ? literalValue(m.initializer) : undefined,
        ...docs(m),
      })),
      ...docs(node),
      ...loc(node, ctx),
    });
  } else if (ts.isTypeAliasDeclaration(node)) {
    ctx.decls.push({
      kind: 'typeAlias',
      name: ns + (exportedName ?? node.name.text),
      typeParams: typeParams(node),
      type: type(node.type),
      ...docs(node),
      ...loc(node, ctx),
    });
  } else if (ts.isModuleDeclaration(node) && node.body && ts.isModuleBlock(node.body)) {
    const prefix = `${ns}${exportedName ?? node.name.text}.`;
    for (const statement of node.body.statements) visitStatement(statement, prefix, ctx);
  } else if (ts.isExportAssignment(node) || ts.isExportDeclaration(node) || ts.isImportDeclaration(node) || ts.isImportEqualsDeclaration(node)) {
    // Handled through the module's export table.
  } else {
    ctx.decls.push({
      kind: 'unsupported',
      name: ns + (exportedName ?? ts.SyntaxKind[node.kind]),
      text: node.getText().slice(0, 200),
      ...loc(node, ctx),
    });
  }
}

function member(node, ctx) {
  const flags = ts.canHaveModifiers(node) ? ts.getCombinedModifierFlags(node) : 0;
  if (flags & ts.ModifierFlags.Private) return null;
  if (node.name && ts.isPrivateIdentifier(node.name)) return null;
  const common = {
    static: (flags & ts.ModifierFlags.Static) !== 0,
    readonly: (flags & ts.ModifierFlags.Readonly) !== 0,
    ...docs(node),
  };
  if (ts.isPropertySignature(node) || ts.isPropertyDeclaration(node)) {
    return { kind: 'property', name: propertyName(node.name), type: type(node.type), optional: !!node.questionToken, ...common };
  }
  if (ts.isMethodSignature(node) || ts.isMethodDeclaration(node)) {
    return {
      kind: 'method',
      name: propertyName(node.name),
      typeParams: typeParams(node),
      params: node.parameters.map(param),
      returns: type(node.type),
      optional: !!node.questionToken,
      ...common,
    };
  }
  if (ts.isConstructorDeclaration(node) || ts.isConstructSignatureDeclaration(node)) {
    return { kind: 'constructor', name: 'constructor', params: node.parameters.map(param), returns: type(node.type), ...common };
  }
  if (ts.isGetAccessorDeclaration(node)) {
    return { kind: 'getter', name: propertyName(node.name), type: type(node.type), ...common };
  }
  if (ts.isSetAccessorDeclaration(node)) {
    return { kind: 'setter', name: propertyName(node.name), type: type(node.parameters[0]?.type), ...common };
  }
  if (ts.isIndexSignatureDeclaration(node)) {
    return { kind: 'index', name: '[]', keyType: type(node.parameters[0]?.type), type: type(node.type), ...common };
  }
  if (ts.isCallSignatureDeclaration(node)) {
    return { kind: 'call', name: '()', params: node.parameters.map(param), returns: type(node.type), ...common };
  }
  return { kind: 'unsupported', name: ts.SyntaxKind[node.kind], text: node.getText().slice(0, 200) };
}

function param(node, index) {
  return {
    name: ts.isIdentifier(node.name) ? node.name.text : `arg${index}`,
    type: type(node.type),
    optional: !!node.questionToken || !!node.initializer,
    rest: !!node.dotDotDotToken,
  };
}

function typeParams(node) {
  return (node.typeParameters ?? []).map((p) => ({
    name: p.name.text,
    ...(p.constraint ? { constraint: type(p.constraint) } : {}),
    ...(p.default ? { default: type(p.default) } : {}),
  }));
}

function heritage(node, token) {
  const clause = node.heritageClauses?.find((c) => c.token === token);
  return (clause?.types ?? []).map(type);
}

const KEYWORDS = new Map([
  [ts.SyntaxKind.AnyKeyword, 'any'],
  [ts.SyntaxKind.UnknownKeyword, 'unknown'],
  [ts.SyntaxKind.NumberKeyword, 'number'],
  [ts.SyntaxKind.BigIntKeyword, 'bigint'],
  [ts.SyntaxKind.StringKeyword, 'string'],
  [ts.SyntaxKind.BooleanKeyword, 'boolean'],
  [ts.SyntaxKind.VoidKeyword, 'void'],
  [ts.SyntaxKind.UndefinedKeyword, 'undefined'],
  [ts.SyntaxKind.NeverKeyword, 'never'],
  [ts.SyntaxKind.ObjectKeyword, 'object'],
  [ts.SyntaxKind.SymbolKeyword, 'symbol'],
  [ts.SyntaxKind.ThisType, 'this'],
]);

/** Serializes a TypeNode. Missing annotations are `any`. */
function type(node) {
  if (!node) return { k: 'keyword', name: 'any' };
  const keyword = KEYWORDS.get(node.kind);
  if (keyword) return { k: 'keyword', name: keyword };
  if (ts.isTypeReferenceNode(node)) {
    return { k: 'ref', name: node.typeName.getText(), args: (node.typeArguments ?? []).map(type) };
  }
  if (ts.isExpressionWithTypeArguments(node)) {
    return { k: 'ref', name: node.expression.getText(), args: (node.typeArguments ?? []).map(type) };
  }
  if (ts.isImportTypeNode(node)) {
    return {
      k: 'ref',
      name: node.qualifier?.getText() ?? 'default',
      args: (node.typeArguments ?? []).map(type),
      from: node.argument.getText().replace(/^['"]|['"]$/g, ''),
    };
  }
  if (ts.isArrayTypeNode(node)) return { k: 'array', elem: type(node.elementType) };
  if (ts.isTupleTypeNode(node)) return { k: 'tuple', elems: node.elements.map(type) };
  if (ts.isUnionTypeNode(node)) return { k: 'union', types: node.types.map(type) };
  if (ts.isIntersectionTypeNode(node)) return { k: 'intersection', types: node.types.map(type) };
  if (ts.isParenthesizedTypeNode(node) || ts.isNamedTupleMember(node)) return type(node.type);
  if (ts.isRestTypeNode(node) || ts.isOptionalTypeNode(node)) return type(node.type);
  if (ts.isLiteralTypeNode(node)) return { k: 'literal', value: literalValue(node.literal) };
  if (ts.isFunctionTypeNode(node) || ts.isConstructorTypeNode(node)) {
    return { k: 'fn', params: node.parameters.map(param), returns: type(node.type) };
  }
  if (ts.isTypeLiteralNode(node)) {
    return { k: 'object', members: node.members.map((m) => member(m, null)).filter(Boolean) };
  }
  if (ts.isTypeOperatorNode(node) && node.operator === ts.SyntaxKind.ReadOnlyKeyword) return type(node.type);
  if (ts.isTypePredicateNode(node)) return { k: 'keyword', name: 'boolean' };
  return { k: 'unsupported', text: node.getText() };
}

function literalValue(node) {
  if (ts.isStringLiteralLike(node)) return node.text;
  if (ts.isNumericLiteral(node)) return Number(node.text);
  if (node.kind === ts.SyntaxKind.TrueKeyword) return true;
  if (node.kind === ts.SyntaxKind.FalseKeyword) return false;
  if (node.kind === ts.SyntaxKind.NullKeyword) return null;
  if (ts.isPrefixUnaryExpression(node) && node.operator === ts.SyntaxKind.MinusToken && ts.isNumericLiteral(node.operand)) {
    return -Number(node.operand.text);
  }
  return node.getText();
}

function propertyName(node) {
  if (ts.isIdentifier(node) || ts.isStringLiteralLike(node) || ts.isNumericLiteral(node)) return node.text;
  return node.getText();
}

// The comment stays as TypeScript prints it (`{@link X}` included) and every
// tag is listed as written; rendering either for Dart is the driver's job.
function docs(node) {
  const parts = [];
  const tags = [];
  for (const doc of ts.getJSDocCommentsAndTags(node)) {
    if (!ts.isJSDoc(doc)) continue;
    if (doc.comment) parts.push(ts.getTextOfJSDocComment(doc.comment));
    for (const tag of doc.tags ?? []) {
      tags.push({
        tag: tag.tagName.text,
        ...(ts.isJSDocParameterTag(tag) ? { name: tag.name.getText() } : {}),
        ...(tag.comment ? { text: ts.getTextOfJSDocComment(tag.comment) } : {}),
      });
    }
  }
  return {
    ...(parts.length ? { docs: parts.join('\n') } : {}),
    ...(tags.length ? { tags } : {}),
  };
}

function loc(node, ctx) {
  if (!ctx) return {};
  const sourceFile = node.getSourceFile();
  const { line } = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile));
  return { file: ctx.file, line: line + 1 };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const pretty = args.includes('--pretty');
  const files = args.filter((a) => a !== '--pretty');
  if (files.length === 0) {
    process.stderr.write('usage: node index.mjs [--pretty] <file.d.ts> [...more]\n');
    process.exit(2);
  }
  try {
    process.stdout.write(JSON.stringify(extract(files), null, pretty ? 2 : 0) + '\n');
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
    process.exit(1);
  }
}
