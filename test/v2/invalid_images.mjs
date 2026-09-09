// Independently constructed from the published BPI2 field/tag table.
// The valid scalar counterpart is also checked by the Zig pure-data suite.
const sections=[[1,0,0,0],[1,9],[1,0,8,42,0,0,0,0,0,0,0],[0],[1,0,0,0,0,0],
  [1,0,0,1,0,0,0,0,0,0,0],[0],[0,0,0],[0]];
function encode(parts=sections) {
  const header=Buffer.alloc(20),directory=[9];header.write('ABL_BPI2');header.writeUInt16LE(2,8);
  let offset=0;for(const[ordinal,part]of parts.entries()){directory.push(ordinal+1,offset,part.length);offset+=part.length;}
  header.writeBigUInt64LE(BigInt(directory.length+offset),12);
  return Buffer.concat([header,Buffer.from(directory),...parts.map((part)=>Buffer.from(part))]);
}
export function invalidImages() {
  const rows=[];
  function changed(name,rejection,change){const bytes=encode();change(bytes);rows.push({name,rejection,bytes});}
  function part(name,rejection,index,value){const parts=sections.map((part)=>[...part]);parts[index]=value;rows.push({name,rejection,bytes:encode(parts)});}
  changed('v1-family','UnsupportedFamily',(bytes)=>bytes.write('ABL_BPI1'));
  changed('flags','InvalidFlags',(bytes)=>bytes.writeUInt16LE(1,10));
  changed('body-length','InvalidLength',(bytes)=>bytes.writeBigUInt64LE((1n<<64n)-1n,12));
  changed('directory-count','InvalidDirectory',(bytes)=>bytes[20]=8);
  changed('directory-gap','InvalidDirectory',(bytes)=>bytes[22]=1);
  changed('profile','UnsupportedProfile',(bytes)=>bytes[48]=2);
  part('schema-unproductive','InvalidSchema',1,[1,12,1,0]);
  part('schema-nonminimal','NonCanonical',1,[0x81,0,9]);
  part('opcode','InvalidTag',5,[1,0,0,1,48,0,0,0,0,0,0]);
  part('return-register','InvalidReference',5,[1,0,0,1,0,0,0,0,0,0,99]);
  part('constructor-capture','InvalidReference',8,[1,0,99,0]);
  part('nominal-regions-max','NonCanonical',7,[0,255,255,255,255,255,255,255,255,255,1,0]);
  const utf=sections.map((part)=>[...part]);utf[1]=[1,11];utf[2]=[1,0,2,1,255];
  rows.push({name:'constant-utf8',rejection:'InvalidUtf8',bytes:encode(utf)});
  return rows;
}
