import { useEffect, useRef, useState } from 'react';
import { ApiError, deliveryApi, goldenApi, type GoldenOrder } from '@/lib/api';
import { deliveryConfirmed, mergeDeliveryOrders, type DeliveryOrder } from '@/lib/deliveryStatus';
import { subscribePanel } from '@/lib/panelRealtime';

const inputStyle='w-full rounded-md border border-white/10 bg-obsidian px-3 py-2';
const buttonStyle='rounded-md border border-white/10 px-4 py-2 disabled:opacity-40';
const validMac=(mac:string)=>/^MK(?::[0-9A-F]{2}){5}$/.test(mac);

// La confirmation consomme un devis précis. Aucune panne réseau ne provoque
// de deuxième POST : seul l'état durable du serveur est relu.
export function GoldenModal({initialMac,onClose}:{initialMac:string;onClose:()=>void}) {
  const [mac,setMac]=useState(initialMac);
  const [sub,setSub]=useState(1);
  const [bouquet,setBouquet]=useState('');
  const [templates,setTemplates]=useState<{id:string;name:string}[]>([]);
  const [quote,setQuote]=useState<GoldenOrder|null>(null);
  const [order,setOrder]=useState<GoldenOrder|null>(null);
  const [receipts,setReceipts]=useState<DeliveryOrder[]>([]);
  const [busy,setBusy]=useState(false);
  const [unknown,setUnknown]=useState(false);
  const [error,setError]=useState('');
  const working=useRef(false);
  const mounted=useRef(true);
  const previousFocus=useRef(document.activeElement);
  const panelReads=useRef(0);
  const blocked=busy||unknown||(order!==null&&order.state!=='refused');
  const normalized=mac.trim().toUpperCase().replaceAll('-',':');
  const applied=!!order?.source_order_id&&!!order?.license_order_id&&
    [order.source_order_id,order.license_order_id].every(id=>deliveryConfirmed(receipts.find(r=>r.order_id===id)));

  useEffect(()=>{mounted.current=true;return()=>{mounted.current=false;if(previousFocus.current instanceof HTMLElement)previousFocus.current.focus();};},[]);
  useEffect(()=>{
    const abort=new AbortController();
    goldenApi.templates(abort.signal).then(r=>setTemplates(r.items)).catch(e=>{
      if(!abort.signal.aborted)setError(e instanceof ApiError?e.message:'Lecture des templates indisponible.');
    });
    return()=>abort.abort();
  },[]);

  useEffect(()=>{
    if(!validMac(normalized))return;
    const abort=new AbortController();let reading=false;
    async function read() {
      if(reading)return;reading=true;
      try {
        const result=await goldenApi.status(normalized,abort.signal);
        if(abort.signal.aborted)return;
        if(result.order){setOrder(result.order);setQuote(null);setUnknown(false);setError('');}
        // Relecture de rattrapage : l'accusé peut précéder la réponse du POST.
        if(result.order&&(panelReads.current++%5===0)) {
          const value=await deliveryApi.orders(normalized,abort.signal);
          if(!abort.signal.aborted)setReceipts(old=>mergeDeliveryOrders(old,value.items));
        }
      } catch { /* Conserver l'état courant ; ne jamais relancer la création. */ }
      finally {reading=false;}
    }
    const unsubscribe=subscribePanel(event=>{
      if(event.mac===normalized&&event.type==='receipt'&&event.order_id) {
        setReceipts(old=>mergeDeliveryOrders(old,[event as DeliveryOrder]).slice(-100));
      }
    });
    const first=setTimeout(()=>{void read();},250);
    const timer=setInterval(()=>{if(!applied)void read();},1000);
    return()=>{abort.abort();clearTimeout(first);clearInterval(timer);unsubscribe();};
  },[normalized,applied]);

  async function mutate(kind:'quote'|'confirm'|'deliver') {
    if(working.current)return;
    working.current=true;setBusy(true);setError('');
    try {
      const response=kind==='quote'?await goldenApi.quote(normalized,sub,bouquet)
        :kind==='confirm'&&quote?await goldenApi.confirm(quote)
        :kind==='deliver'&&order?await goldenApi.deliver(order.id):null;
      if(!mounted.current||!response)return;
      if(kind==='quote')setQuote(response.order);
      else {setOrder(response.order);setQuote(null);}
    } catch(e) {
      if(!mounted.current)return;
      if(kind==='confirm') {
        // Même un timeout du navigateur peut suivre une création réussie.
        setUnknown(true);setQuote(null);
        setError('Confirmation non reçue. Vérification de l’état en cours ; aucune nouvelle création ne sera envoyée.');
      } else setError(e instanceof ApiError?e.message:'Opération indisponible. Réessayez plus tard.');
    } finally {working.current=false;if(mounted.current)setBusy(false);}
  }
  function changeMac(value:string) {setMac(value);setQuote(null);setOrder(null);setReceipts([]);panelReads.current=0;}

  return <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4">
    <section role="dialog" aria-modal="true" aria-labelledby="golden-title"
      onKeyDown={event=>{
        if(event.key==='Escape'&&!busy){event.preventDefault();onClose();}
        if(event.key==='Tab') {
          const controls=event.currentTarget.querySelectorAll<HTMLElement>('button:not(:disabled),input:not(:disabled),select:not(:disabled)');
          const first=controls[0],last=controls[controls.length-1];
          if(event.shiftKey&&document.activeElement===first){event.preventDefault();last?.focus();}
          else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first?.focus();}
        }
      }}
      className="max-h-[90vh] w-full max-w-lg overflow-y-auto rounded-2xl border border-white/10 bg-midnight p-6 shadow-2xl">
      <div className="mb-4 flex items-center justify-between gap-3">
        <h2 id="golden-title" className="text-xl font-semibold">Golden</h2>
        <button type="button" className={buttonStyle} disabled={busy} onClick={onClose}>Fermer</button>
      </div>
      <p className="mb-4 text-sm text-ink-secondary">Créez une ligne Strong pour cet appareil. Le coût sera confirmé avant la création.</p>
      <form onSubmit={e=>{e.preventDefault();void mutate('quote');}} className="space-y-4">
        <label className="block">Adresse MAC du client
          <input autoFocus aria-label="Adresse MAC du client" className={inputStyle} value={mac} disabled={blocked}
            onChange={e=>changeMac(e.target.value)} placeholder="MK:11:22:33:44:55" autoComplete="off" required />
        </label>
        <label className="block">Durée
          <select aria-label="Durée" className={inputStyle} value={sub} disabled={blocked}
            onChange={e=>{setSub(Number(e.target.value));setQuote(null);}}>
            {[1,3,6,12].map(months=><option key={months} value={months}>{months} mois</option>)}
          </select>
        </label>
        <label className="block">Template Strong
          <select aria-label="Template Strong" className={inputStyle} value={bouquet} disabled={blocked}
            onChange={e=>{setBouquet(e.target.value);setQuote(null);}} required>
            <option value="">Choisir un template</option>
            {templates.map(item=><option key={item.id} value={item.id}>{item.name}</option>)}
          </select>
        </label>
        {!quote&&!blocked&&<button type="submit" className={`${buttonStyle} bg-accent text-white`}
          disabled={!validMac(normalized)||!bouquet||busy}>Golden</button>}
      </form>
      {quote&&<div className="mt-5 space-y-3 rounded-xl border border-accent/40 p-4" role="region" aria-label="Confirmation Golden">
        <p className="font-semibold">Coût prévu : {quote.cost} crédit(s)</p>
        <p className="text-sm">{quote.mac} · {quote.sub} mois · {quote.bouquet_name}</p>
        <p className="text-sm text-ink-secondary">Compte {quote.key_label} · Solde {quote.credits_before} crédits.<br />Montant calculé selon le tarif administrateur configuré.</p>
        <button type="button" className={`${buttonStyle} bg-accent text-white`} disabled={busy}
          onClick={()=>void mutate('confirm')}>Confirmer et dépenser {quote.cost} crédit(s)</button>
        <button type="button" className={`${buttonStyle} ml-2`} disabled={busy} onClick={()=>setQuote(null)}>Annuler</button>
      </div>}
      {busy&&<p role="status" className="mt-4">{quote?'Création en cours…':'Préparation en cours…'}</p>}
      {error&&<p role="alert" className="mt-4 text-sm text-accent">{error}</p>}
      {order&&<div aria-live="polite" className="mt-5 space-y-3 rounded-xl border border-white/10 p-4">
        <p className="font-mono text-xs">{order.mac}</p>
        {applied?<p className="font-semibold">Golden appliqué sur l’appareil</p>
          :order.state==='uncertain'?<p>Résultat Strong incertain. Vérification manuelle requise ; aucune autre clé ni nouvelle création ne sera utilisée.</p>
          :order.state==='refused'?<p>Création non lancée. Rechargez un devis après vérification des crédits et des listes.</p>
          :['preparing','creating'].includes(order.state)?<p>Création en cours. La page vérifie son état sans la relancer.</p>
          :<p>Ligne créée. En attente de l’application sur l’appareil.</p>}
        {order.state==='created'&&!busy&&<button type="button" className={buttonStyle} onClick={()=>void mutate('deliver')}>Réessayer uniquement la livraison</button>}
        {order.state==='refused'&&!busy&&<button type="button" className={buttonStyle} onClick={()=>{setOrder(null);setUnknown(false);}}>Nouveau devis</button>}
      </div>}
    </section>
  </div>;
}
