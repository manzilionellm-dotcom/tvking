import assert from 'node:assert/strict';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
export async function supportParcours({page,check}) {
 const token=randomBytes(32).toString('base64url');
 const id=createHash('sha256').update(token).digest('hex');
 const url=`http://127.0.0.1:8787/api/support/${id}`;
 const client=async(method='GET',body)=>{
  const r=await fetch(url,{method,headers:{'Content-Type':'application/json','X-Support-Token':token},body:body?JSON.stringify(body):undefined});
  return {status:r.status,data:await r.json()};
 };
 assert.equal((await client('POST',{client_id:randomUUID(),body:'Bonjour, besoin d’aide pour le guide.',device_label:'MK:CC:11:22:33:44'})).status,201);
 await page.goto('http://127.0.0.1:5173/support');
 await page.getByRole('heading',{name:'Chat privé',exact:true}).waitFor();
 await page.getByRole('button').filter({hasText:'MK:CC:11:22:33:44'}).click();
 await page.getByRole('log').getByText('Bonjour, besoin d’aide pour le guide.',{exact:true}).waitFor();
 await page.getByLabel('Votre réponse',{exact:true}).fill('Bonjour ! Nous regardons cela ensemble.');
 await page.getByRole('button',{name:'Envoyer',exact:true}).click();
 await page.getByRole('log').getByText('Bonjour ! Nous regardons cela ensemble.',{exact:true}).waitFor();
 const response=await client();
 assert.equal(response.data.items.at(-1).sender,'owner');
 assert.equal(response.data.items.at(-1).body,'Bonjour ! Nous regardons cela ensemble.');
 assert.equal(response.data.unread,1);
 await client('PATCH',{read_through:response.data.items.at(-1).seq});
 await page.getByRole('log').getByText(/ · Lu$/).waitFor();
 check('chat : client authentifié → vrai formulaire panel → réponse relue par le client → accusé Lu',true);
 const blocked=await fetch(url);assert.equal(blocked.status,401);
 check('chat : URL de conversation inutilisable sans son secret',true);
 await page.screenshot({path:new URL('./.state/chat-desktop.png',import.meta.url).pathname,fullPage:true});
 await page.setViewportSize({width:390,height:844});
 assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
 await page.screenshot({path:new URL('./.state/chat-mobile.png',import.meta.url).pathname,fullPage:true});
 await page.setViewportSize({width:1280,height:800});
}
