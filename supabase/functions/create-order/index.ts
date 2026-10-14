import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.49.1";
const origin = "https://bhavishyacodz.github.io";
const cors = {"Access-Control-Allow-Origin":origin,"Access-Control-Allow-Headers":"authorization, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS","Vary":"Origin"};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json"}});
Deno.serve(async (req:Request)=>{
 if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
 if(req.method!=="POST" || req.headers.get("origin")!==origin) return reply({error:"Not allowed"},403);
 const keyId=Deno.env.get("RAZORPAY_KEY_ID"), keySecret=Deno.env.get("RAZORPAY_KEY_SECRET");
 const url=Deno.env.get("SUPABASE_URL"), serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!keyId||!keySecret||!url||!serviceKey) return reply({error:"Payment service is not configured yet"},503);
 let body:{registration_id?:string}; try{body=await req.json()}catch{return reply({error:"Invalid request"},400)}
 if(!body.registration_id || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(body.registration_id)) return reply({error:"Invalid registration reference"},400);
 const db=createClient(url,serviceKey,{auth:{persistSession:false}});
 const {data:row,error}=await db.from("registrations").select("id,full_name,payment_status,payment_reference").eq("id",body.registration_id).maybeSingle();
 if(error||!row) return reply({error:"Registration not found"},404);
 if(row.payment_status==="paid") return reply({error:"This registration is already marked paid"},409);
 const auth="Basic "+btoa(keyId+":"+keySecret);
 // Reuse an existing unpaid order to avoid creating multiple payment orders for one registration.
 if(row.payment_reference?.startsWith("order_")){
   const existing=await fetch("https://api.razorpay.com/v1/orders/"+encodeURIComponent(row.payment_reference),{headers:{Authorization:auth}});
   if(existing.ok){const old=await existing.json();if(old.status==="created" && old.amount===9900)return reply({keyId,orderId:old.id,amount:old.amount,currency:old.currency});}
 }
 const orderRes=await fetch("https://api.razorpay.com/v1/orders",{method:"POST",headers:{Authorization:auth,"Content-Type":"application/json"},body:JSON.stringify({amount:9900,currency:"INR",receipt:row.id.slice(0,40),notes:{registration_id:row.id,service:"Crimson Romance ₹99 service fee"}})});
 if(!orderRes.ok) return reply({error:"Could not create payment order"},502);
 const order=await orderRes.json();
 const {error:updateError}=await db.from("registrations").update({payment_reference:order.id}).eq("id",row.id).eq("payment_status","pending");
 if(updateError)return reply({error:"Could not link payment order to registration"},500);
 return reply({keyId,orderId:order.id,amount:order.amount,currency:order.currency});
});