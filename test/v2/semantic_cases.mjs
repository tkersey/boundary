// Typed environmental scripts for the independent source semantics.
// No ERQ2 identity or future State is invented here.
export const programNames = ['lexical','deep','recursive','choices-all','choices-first','generator',
  'state-local','state-shared','resource-scalar','resource-pair','answers','scoped-reader','writer-raise',
  'scheduler','queens-dfs','queens-bfs','cell-order','nested','shallow','injection','indexed','abort-custody',
  'unwind','reentrant','cloned','clause-abort','bounded-values','scalar-contracts','ownership','shallow-resumptions','shallow-injection',
  'handle-operand-order','protect-operand-order','successor-state','clause-payload','yielding-cleanup','borrow-operands'];
const scalar=(value)=>{const bytes=Buffer.alloc(8);bytes.writeBigUInt64LE(BigInt(value));return [...bytes];};
export const cases=[];
function add(name,program,initial=[],responses=[],cancellations=[]) { cases.push({name,program,initial,responses,cancellations}); }
for(const name of ['deep','choices-all','choices-first','state-local','state-shared','answers','writer-raise','cell-order','nested','bounded-values']) add(name,name);
add('lexical','lexical',scalar(40)); add('recursive-10000','recursive',scalar(10000));
for(const name of ['shallow','injection','shallow-injection']) for(const input of [0,1]) add(`${name}-${input}`,name,[input]);
for(const name of ['generator','scheduler','reentrant','cloned','ownership']) add(name,name,[],name==='generator'?[[]]:[]);
for(const name of ['resource-scalar','resource-pair']) {
  add(name,name,[],[scalar(41),[],[]]);
  add(`${name}-cancel-body`,name,[],[scalar(41),[]],[{at:1,reason:'stop',preservesRequest:false},{at:2,reason:'later',preservesRequest:true}]);
  add(`${name}-cancel-cleanup`,name,[],[scalar(41),[],[]],[{at:2,reason:'stop',preservesRequest:true},{at:2,reason:'later',preservesRequest:true}]);
}
add('scoped-reader','scoped-reader',[],[[],[],[]]);
add('indexed','indexed',[],[scalar(37),[1]]);
add('abort-owned','abort-custody',[0],[[]]); add('abort-empty','abort-custody',[1]);
add('clause-abort','clause-abort',[],[[]]);
for(const name of ['queens-dfs','queens-bfs']) add(name,name,[],[scalar(201),[],[],scalar(202),[],[]]);
for(const primary of [0,1]) for(const cancel of [false,true]) add(`unwind-${primary}-${cancel?'cancel':'continue'}`,'unwind',[primary],[[],[]],cancel?[{at:0,reason:'stop',preservesRequest:true},{at:0,reason:'later',preservesRequest:true}]:[]);
for(const primary of [0,1]) for(const cancel of [false,true]) add(`yielding-cleanup-${primary}-${cancel?'cancel':'continue'}`,'yielding-cleanup',[primary],[[],[]],cancel?[{at:0,reason:'stop',preservesRequest:false},{at:2,reason:'later',preservesRequest:false}]:[]);
for(let index=0;index<19;index++) add(`scalar-contract-${index}`,'scalar-contracts',[index]);
add('shallow-resumptions','shallow-resumptions');
for (const name of ['handle-operand-order','protect-operand-order','successor-state','clause-payload']) add(name,name);
for(let index=0;index<32;index++) add(`borrow-operands-${index}`,'borrow-operands',[index]);
for(let index=32;index<42;index++) add(`custody-order-${index-32}`,'borrow-operands',[index],[[],[]]);
for(let index=42;index<53;index++) add(`operand-failure-${index-42}`,'borrow-operands',[index],[[],[]]);
