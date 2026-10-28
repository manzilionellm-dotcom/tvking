// Parcours du vrai panel compilé, toutes les API interceptées avec des fixtures.
// Aucun compte, crédit ni serveur de production n'est utilisé.
const {chromium}=require(process.env.PANEL_PLAYWRIGHT_MODULE || 'playwright');
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.launch({headless:true,executablePath:process.env.PANEL_BROWSER_EXECUTABLE || undefined,args:['--no-sandbox']});
 const page=await browser.newPage({viewport:{width:1440,height:1000}});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 let activations=0,sources=0,polls=0;
 await page.addInitScript(()=>localStorage.setItem('auth_token','fixture-not-a-real-token'));
 await page.route('**/*',async route=>{
  const u=new URL(route.request().url());
  if(u.origin==='http://127.0.0.1:4173')return route.continue();
  if(u.origin!=='https://api.zuno8k.com')return route.abort();
  if(route.request().method()==='OPTIONS') return route.fulfill({status:204,headers:{'Access-Control-Allow-Origin':'http://127.0.0.1:4173','Access-Control-Allow-Headers':'Authorization, Content-Type','Access-Control-Allow-Methods':'GET, POST, PUT'}});
  let body={items:[]},status=200;
  if(u.pathname.endsWith('/auth/me')||u.pathname.endsWith('/me'))body={user:{id:'fixture',role:'super_admin',email:'fixture@example.invalid',credit_balance:null}};
  else if(u.pathname==='/api/v1/apps')body={items:[{id:'app_7motion',name:'7 MOTION'}]};
  else if(u.pathname==='/api/v1/activate'){
   activations++;body={ok:true,license_id:'lic_fixture',device_id:'dev_fixture',customer_id:'cus_fixture',mac:'MK:11:22:33:44:55',plan:'monthly',expires_at:1795900000000,credits_charged:0,credit_balance:null,renewed:false,order_id:'ord_license123',trace_id:'trace_fixture123'};
  } else if(u.pathname.startsWith('/api/v1/sources/')){
   sources++;
   if(sources===1){status=503;body={error:'fixture_failure'};}
   else body={ok:true,mac:'MK:11:22:33:44:55',count:1,rev:42,order_id:'ord_source123'};
  } else if(u.pathname==='/api/v1/orders'){
   polls++;body={items:[{order_id:'ord_license123',kind:'activate',state:'applied'},...(sources>1?[{order_id:'ord_source123',kind:'source',state:polls>2?'applied':'received',config_rev:42,applied_rev:42}]:[])]};
  }
  return route.fulfill({status,contentType:'application/json',headers:{'Access-Control-Allow-Origin':'http://127.0.0.1:4173','Access-Control-Allow-Headers':'Authorization, Content-Type'},body:JSON.stringify(body)});
 });
 await page.goto('http://127.0.0.1:4173/activate');
 await page.getByPlaceholder('MK:1A:2B:3C:4D:5E').fill('MK:11:22:33:44:55');
 await page.getByRole('button',{name:'+ Ajouter une source',exact:true}).click();
 await page.getByPlaceholder('http://exemple.test:8080',{exact:true}).fill('https://fixture.example.invalid');
 await page.getByPlaceholder('Utilisateur',{exact:true}).fill('fixture-user');
 await page.getByPlaceholder('Mot de passe',{exact:true}).fill('fixture-password');
 await page.getByRole('button',{name:'Activer',exact:true}).click();
 await page.getByText('Licence enregistrée',{exact:true}).waitFor();
 await page.getByRole('button',{name:'Réessayer uniquement l’envoi des listes'}).click();
 await page.getByText('Liste : Appliqué sur l’appareil',{exact:true}).waitFor({timeout:6000});
 assert.equal(activations,1);assert.equal(sources,2);assert.deepEqual(errors,[]);
 if(process.env.PANEL_CAPTURE_DIR) {
  require('node:fs').mkdirSync(process.env.PANEL_CAPTURE_DIR,{recursive:true});
  await page.screenshot({path:process.env.PANEL_CAPTURE_DIR+'/panel-delivery.png',fullPage:true});
 }
 const count=polls;await page.waitForTimeout(1600);assert.equal(polls,count,'polling stops after confirmation');
 await page.getByRole('button',{name:'Activer un autre appareil'}).click();
 assert.equal(await page.getByPlaceholder('MK:1A:2B:3C:4D:5E').inputValue(),'MK:');
 await page.setViewportSize({width:390,height:844});
 assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth+1),true,'no horizontal overflow on phone');
 console.log(JSON.stringify({passed:true,activations,sources,polls,errors,checks:['partial failure retained','source-only retry','correct revision confirmed','polling stopped','next-device reset']}));
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1);});
