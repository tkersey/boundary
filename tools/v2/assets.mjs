// Deterministic release containers and inert source provenance. No evaluator.
import { createHash } from 'node:crypto';
import { readFile, writeFile, mkdir, lstat } from 'node:fs/promises';
import { realpathSync } from 'node:fs';
import { join } from 'node:path';
import { gzipSync, gunzipSync } from 'node:zlib';
import { execFileSync } from 'node:child_process';

export const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
export const json = (value) => Buffer.from(JSON.stringify(value, null, 2) + '\n');
function sourceGit(root) {
  const cwd = realpathSync(root);
  const env = Object.fromEntries(Object.entries(process.env).filter(([name]) => !name.startsWith('GIT_')));
  const git = (...args) => execFileSync('git', ['--no-replace-objects', '-c', 'core.fsmonitor=false', ...args], { cwd, env, maxBuffer: 64 << 20 });
  if (realpathSync(git('rev-parse', '--show-toplevel').toString().trim()) !== cwd) throw new Error('source must select the repository root');
  return git;
}
export function safeName(name) {
  if (typeof name !== 'string' || !/^[A-Za-z0-9_.\-/]+$/.test(name) || name.startsWith('/') || name.split('/').some((part)=>!part || part === '.' || part === '..')) throw new Error(`unsafe asset name: ${name}`);
  return name;
}
export function tarGzip(entries) {
  const blocks = [], seen = new Set();
  for (const entry of [...entries].sort((a,b)=>a.name < b.name ? -1 : a.name > b.name ? 1 : 0)) {
    const name = safeName(entry.name), bytes = Buffer.from(entry.bytes);
    if (seen.has(name) || Buffer.byteLength(name) > 100) throw new Error(`duplicate or long archive path: ${name}`);
    seen.add(name);
    const header = Buffer.alloc(512);
    header.write(name, 0, 100, 'utf8');
    const octal = (offset,length,value) => {
      const text = value.toString(8).padStart(length-1,'0');
      if(text.length !== length-1) throw new Error('tar field overflow');
      header.write(text+'\0',offset,length,'ascii');
    };
    octal(100,8,entry.executable ? 0o755 : 0o644); octal(108,8,0); octal(116,8,0);
    octal(124,12,bytes.length); octal(136,12,0);
    header.fill(32,148,156); header[156]=48;
    header.write('ustar\0',257,6,'ascii'); header.write('00',263,2,'ascii');
    const checksum=header.reduce((sum,byte)=>sum+byte,0);
    header.write(checksum.toString(8).padStart(6,'0')+'\0 ',148,8,'ascii');
    blocks.push(header,bytes,Buffer.alloc((512-bytes.length%512)%512));
  }
  blocks.push(Buffer.alloc(1024));
  return gzipSync(Buffer.concat(blocks), { level: 9 });
}
export function readTarGzip(input) {
  const bytes=gunzipSync(input, { maxOutputLength: 128 << 20 }), entries=[], seen=new Set();
  let offset=0;
  const text=(field)=>field.subarray(0,field.indexOf(0)===-1?field.length:field.indexOf(0)).toString('utf8');
  const number=(field)=>{ const value=text(field).trim(); if(!/^[0-7]+$/.test(value)) throw new Error('invalid tar integer'); const n=Number.parseInt(value,8); if(!Number.isSafeInteger(n)) throw new Error('tar integer overflow'); return n; };
  for(;;) {
    if(offset+512>bytes.length) throw new Error('truncated tar');
    const header=bytes.subarray(offset,offset+512); offset+=512;
    if(header.every((byte)=>byte===0)) {
      if(bytes.length-offset<512 || bytes.subarray(offset).some((byte)=>byte!==0)) throw new Error('invalid tar terminator');
      return entries;
    }
    const sum=header.reduce((sum,byte,i)=>sum+(i>=148&&i<156?32:byte),0);
    if(sum!==number(header.subarray(148,156))) throw new Error('tar checksum mismatch');
    const name=safeName(text(header.subarray(0,100)));
    if(seen.has(name)||header[156]!==48||text(header.subarray(257,263))!=='ustar'||header.subarray(345,500).some((byte)=>byte!==0)) throw new Error('unsupported archive entry');
    seen.add(name);
    const length=number(header.subarray(124,136)), mode=number(header.subarray(100,108));
    if(length>bytes.length-offset) throw new Error('truncated archive entry');
    if(mode!==0o644&&mode!==0o755) throw new Error('unexpected archive permissions');
    const content=bytes.subarray(offset,offset+length); offset+=length;
    const padding=(512-length%512)%512;
    if(offset+padding>bytes.length||bytes.subarray(offset,offset+padding).some((byte)=>byte!==0)) throw new Error('nonzero archive padding');
    offset+=padding; entries.push({name,bytes:Buffer.from(content),executable:mode===0o755});
  }
}
export function indexedBundle(entries) {
  let offset=0;
  const sorted=[...entries].sort((a,b)=>a.name < b.name ? -1 : a.name > b.name ? 1 : 0), seen=new Set();
  const files=sorted.map(({name,bytes})=>{
    safeName(name); if(seen.has(name))throw new Error(`duplicate bundle path: ${name}`);seen.add(name);
    const row={name,offset,length:bytes.length,sha256:sha256(bytes)};offset+=bytes.length;return row;
  });
  return {files,bytes:Buffer.concat(sorted.map(({bytes})=>bytes))};
}
export function readBundle(manifest,bytes) {
  const result=new Map();let offset=0;
  for(const row of manifest.files) {
    safeName(row.name);
    if(result.has(row.name)||row.offset!==offset||!Number.isSafeInteger(row.length)||row.length<0||row.length>bytes.length-offset)throw new Error('invalid bundle directory');
    const value=bytes.subarray(offset,offset+row.length);offset+=row.length;
    if(sha256(value)!==row.sha256)throw new Error('bundle digest mismatch');
    result.set(row.name,Buffer.from(value));
  }
  if(offset!==bytes.length)throw new Error('trailing bundle content');
  return result;
}
export async function sourceIdentity(root) {
  const readGit=sourceGit(root), git=(...args)=>readGit(...args).toString().trim();
  const head=git('rev-parse','HEAD'), tree=git('rev-parse','HEAD^{tree}');
  const dirty=git('status','--porcelain','--untracked-files=all').length!==0;
  const names=git('ls-files','--cached','--others','--exclude-standard','-z').split('\0').filter((name)=>name&&name!=='.learnings.jsonl'&&!name.startsWith('.ledger/'));
  const files=[];
  for(const name of [...new Set(names)].sort()) {
    const path=join(root,safeName(name));
    const metadata=await lstat(path).catch((error)=>{if(error.code==='ENOENT')return null;throw error;});
    if(!metadata)continue;
    if(!metadata.isFile())throw new Error(`source must be a regular file: ${name}`);
    files.push({name,sha256:sha256(await readFile(path))});
  }
  return {git:{head,tree,dirty},filesSha256:sha256(json(files)),fileScope:'Git tracked and nonignored untracked regular files, excluding .ledger and retired .learnings.jsonl evidence stores',files};
}
export async function writeAssets(directory, entries) {
  await mkdir(directory,{recursive:true});
  for(const {name,bytes} of entries) {
    if(safeName(name).includes('/'))throw new Error('release assets must be flat');
    await writeFile(join(directory,name),bytes);
  }
  const sums=entries.map(({name,bytes})=>`${sha256(bytes)}  ${name}\n`).sort().join('');
  await writeFile(join(directory,'SHA256SUMS'),sums);
}
export async function verifyAssets(directory, names) {
  const sums=await readFile(join(directory,'SHA256SUMS'),'utf8'), rows=new Map();
  for(const line of sums.trimEnd().split('\n')) {
    const match=/^([a-f0-9]{64})  ([A-Za-z0-9_.-]+)$/.exec(line);
    if(!match||rows.has(match[2]))throw new Error('invalid asset checksums'); rows.set(match[2],match[1]);
  }
  if(rows.size!==names.length||names.some((name)=>!rows.has(name)))throw new Error('unexpected release inventory');
  const output=new Map();
  for(const name of names) {const bytes=await readFile(join(directory,name));if(sha256(bytes)!==rows.get(name))throw new Error(`asset digest mismatch: ${name}`);output.set(name,bytes);}
  return output;
}
