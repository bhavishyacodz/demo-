import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.49.1";
const origin="https://bhavishyacodz.github.io";
const cors={"Access-Control-Allow-Origin":origin,"Access-Control-Allow-Headers":"authorization, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin"};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
function hex(bytes:ArrayBuffer){return [...new Uint8Array(bytes)].map(b=>b.toString(16).padStart(2,"0")).join("")}
Deno.serve(async(req:Request)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST"||req.headers.get("origin")!==origin)return reply({error:"Not allowed"},403);
 const secret=Deno.env.get("RAZORPAY_KEY_SECRET"),url=Deno.env.get("SUPABASE_URL"),serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!secret||!url||!serviceKey)return reply({error:"Payment verification is not configured"},503);
 let b:{registration_id?:string;razorpay_order_id?:string;razorpay_payment_id?:string;razorpay_signature?:string};try{b=await req.json()}catch{return reply({error:"Invalid request"},400)}
 if(!b.registration_id||!b.razorpay_order_id||!b.razorpay_payment_id||!b.razorpay_signature)return reply({error:"Missing payment verification fields"},400);
 const key=await crypto.subtle.importKey("raw",new TextEncoder().encode(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
 const sig=hex(await crypto.subtle.sign("HMAC",key,new TextEncoder().encode(b.razorpay_order_id+"|"+b.razorpay_payment_id)));
 if(sig.length!==b.razorpay_signature.length||![...sig].every((c,i)=>c===b.razorpay_signature![i]))return reply({error:"Payment signature is invalid"},400);
 const keyId=Deno.env.get("RAZORPAY_KEY_ID");
 if(!keyId)return reply({error:"Payment provider is not configured"},503);
 const paymentRes=await fetch("https://api.razorpay.com/v1/payments/"+encodeURIComponent(b.razorpay_payment_id),{headers:{Authorization:"Basic "+btoa(keyId+":"+secret)}});
 if(!paymentRes.ok)return reply({error:"Could not verify payment status with the payment provider"},502);
 const payment=await paymentRes.json();
 if(payment.order_id!==b.razorpay_order_id||payment.amount!==9900||payment.currency!=="INR")return reply({error:"Payment does not match the expected order amount"},400);
 if(payment.status!=="captured")return reply({error:"Payment is not captured yet; status remains pending",payment_status:payment.status},202);
 const db=createClient(url,serviceKey,{auth:{persistSession:false}});
 const {data:row,error}=await db.from("registrations").select("id,payment_status,payment_reference").eq("id",b.registration_id).maybeSingle();
 if(error||!row)return reply({error:"Registration not found"},404);
 if(row.payment_status==="paid")return reply({ok:true,alreadyPaid:true});
 if(row.payment_reference!==b.razorpay_order_id)return reply({error:"Order does not match this registration"},409);
 const {data:updated,error:updateError}=await db.from("registrations").update({payment_status:"paid",payment_reference:b.razorpay_payment_id,work_status:"Paid"}).eq("id",row.id).eq("payment_status","pending").select("id").maybeSingle();
 if(updateError||!updated)return reply({error:"Payment verified but database update needs manual review"},500);
 return reply({ok:true,status:"paid"});
});