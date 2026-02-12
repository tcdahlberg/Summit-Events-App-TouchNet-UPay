# TouchNet UPay Proxy Server Setup Guide

## Why a Proxy Server is Required

### The Problem

**TouchNet UPay Security Requirement:**
- TouchNet requires **static IP addresses** for all systems calling their REST API
- They maintain an IP whitelist for security purposes
- Only requests from whitelisted IPs are allowed through their firewall

**Salesforce Limitation:**
- Salesforce **does not provide static IP addresses** for outbound connections
- Salesforce IPs can change without notice
- This makes it impossible to whitelist Salesforce directly with TouchNet

### The Solution

Deploy a **proxy server with static IP addresses** that:
1. Receives payment callbacks from TouchNet
2. Forwards them to your Salesforce REST endpoint
3. Returns Salesforce's response back to TouchNet

```
┌──────────────┐         ┌──────────────┐         ┌──────────────┐
│   TouchNet   │ ──────> │ Proxy Server │ ──────> │  Salesforce  │
│   UPay       │ Static  │ (AWS Lambda) │ Dynamic │  REST API    │
│   Gateway    │   IP    │ + Load Bal.  │   IP    │              │
└──────────────┘         └──────────────┘         └──────────────┘
                            ↑
                            │
                    Static IP: 1.2.3.4
                    (Whitelisted by TouchNet)
```

---

## Architecture Overview

### Components

1. **AWS Lambda Function**
   - Runs the NodeJS proxy code
   - Receives POST from TouchNet
   - Forwards to Salesforce REST endpoint
   - Returns response to TouchNet

2. **Application Load Balancer (ALB)**
   - Provides static IP addresses (via Elastic IPs)
   - Routes traffic to Lambda function
   - Handles SSL/TLS termination

3. **Elastic IP Addresses**
   - Static IPs assigned to ALB
   - Provided to TouchNet for whitelisting
   - Never change unless manually reassigned

---

## Prerequisites

- AWS Account with appropriate permissions
- AWS CLI installed and configured
- Node.js installed (for local testing)
- Your Salesforce site domain
- TouchNet UPay account representative contact

---

## Step 1: Deploy NodeJS Proxy to AWS Lambda

### 1.1 Create Lambda Function

**Via AWS Console:**

1. Navigate to **AWS Lambda** console
2. Click **Create function**
3. Choose **Author from scratch**
4. Configure:
   - **Function name:** `touchnet-salesforce-proxy`
   - **Runtime:** Node.js 20.x (or latest LTS)
   - **Architecture:** x86_64
   - **Execution role:** Create a new role with basic Lambda permissions

5. Click **Create function**

---

### 1.2 Deploy Proxy Code

**Copy the proxy code:**

The proxy code is located at:
```
unpackaged/src/touchNet-Salesforce-NodeJS-Proxy.js
```

**Update the code with your Salesforce domain:**

```javascript
const options = {
    hostname: 'YOUR-DOMAIN.my.site.com', // ← CHANGE THIS
    path: '/services/apexrest/upaypaymentreceive',
    method: 'POST',
    port: 443,
    headers: {
        'Content-Type': 'application/json'
    },
};
```

**Replace:**
- `YOUR-DOMAIN.my.site.com` with your actual Salesforce Experience Cloud site domain
- If using a subdirectory, update `path` to include it (e.g., `/events/services/apexrest/upaypaymentreceive`)

**Deploy to Lambda:**

1. In Lambda console, go to **Code** tab
2. Delete the default `index.js` content
3. Paste the updated proxy code
4. Rename file to `index.js` (or update handler to `index.handler`)
5. Click **Deploy**

---

### 1.3 Configure Lambda Settings

**Memory and Timeout:**
1. Go to **Configuration** → **General configuration**
2. Set:
   - **Memory:** 256 MB (more than sufficient)
   - **Timeout:** 30 seconds (allows time for Salesforce to respond)

**Environment Variables (Optional):**
You can externalize the Salesforce domain:

```javascript
// In Lambda code
const salesforceDomain = process.env.SALESFORCE_DOMAIN || 'default-domain.my.site.com';
```

Then set in **Configuration** → **Environment variables**:
- Key: `SALESFORCE_DOMAIN`
- Value: `your-domain.my.site.com`

---

### 1.4 Test Lambda Function

**Create a test event:**

1. Go to **Test** tab
2. Create new test event
3. Use this JSON (simulates TouchNet callback):

```json
{
  "body": "cG10X3N0YXR1cz1zdWNjZXNzJnRwZ190cmFuc19pZD1UMTIzNDUmcG10X2FtdD0xNTAuMDAmcG10X2RhdGU9MDIvMTIvMjAyNiZTRUFfU0VDVVJFPWVuY3J5cHRlZC10b2tlbg==",
  "headers": {
    "content-type": "application/x-www-form-urlencoded"
  }
}
```

4. Click **Test**
5. Check response - should see successful forward to Salesforce

---

## Step 2: Set Up Application Load Balancer with Static IPs

### 2.1 Create VPC and Subnets (If Needed)

**Note:** If you already have a VPC, skip to 2.2

1. Navigate to **VPC** console
2. Create VPC with:
   - At least 2 public subnets in different Availability Zones
   - Internet Gateway attached
   - Route table configured for internet access

---

### 2.2 Allocate Elastic IP Addresses

1. Navigate to **EC2** → **Elastic IPs**
2. Click **Allocate Elastic IP address**
3. Choose **Amazon's pool of IPv4 addresses**
4. Click **Allocate**
5. **Repeat for second Availability Zone** (2 IPs minimum for HA)
6. **Note down the IP addresses** - these will be provided to TouchNet

Example:
- Elastic IP 1: `54.123.45.67`
- Elastic IP 2: `54.123.45.68`

---

### 2.3 Create Target Group for Lambda

1. Navigate to **EC2** → **Target Groups**
2. Click **Create target group**
3. Configure:
   - **Target type:** Lambda function
   - **Target group name:** `touchnet-proxy-lambda-tg`
   - **Protocol version:** HTTP1
   - **Health check path:** `/health` (or `/`)
4. Click **Next**
5. Select your Lambda function (`touchnet-salesforce-proxy`)
6. Click **Create target group**

---

### 2.4 Create Application Load Balancer

1. Navigate to **EC2** → **Load Balancers**
2. Click **Create Load Balancer**
3. Choose **Application Load Balancer**
4. Configure:
   - **Name:** `touchnet-proxy-alb`
   - **Scheme:** Internet-facing
   - **IP address type:** IPv4
   - **VPC:** Select your VPC
   - **Subnets:** Select 2+ public subnets in different AZs
5. **Security groups:**
   - Create new security group: `touchnet-alb-sg`
   - Inbound rules:
     - Type: HTTPS, Port: 443, Source: `0.0.0.0/0` (or TouchNet IPs if known)
     - Type: HTTP, Port: 80, Source: `0.0.0.0/0` (for testing, optional)
6. **Listeners and routing:**
   - Protocol: HTTPS, Port: 443
   - Default action: Forward to `touchnet-proxy-lambda-tg`
   - SSL certificate: Select or import your SSL certificate
7. Click **Create load balancer**

---

### 2.5 Associate Elastic IPs with ALB

**Note:** ALB doesn't directly support Elastic IPs. You need Network Load Balancer (NLB) in front of ALB, or use Global Accelerator.

**Option A: Use Network Load Balancer (Recommended)**

1. Create **Network Load Balancer** with Elastic IPs
2. Configure NLB to forward to ALB
3. TouchNet calls NLB → NLB forwards to ALB → ALB invokes Lambda

**Option B: Use AWS Global Accelerator (Enterprise Solution)**

1. Create Global Accelerator
2. Get static IPs from Accelerator
3. Point to ALB as endpoint

**Option C: Simplified - Use NLB Directly with Lambda**

1. Create Network Load Balancer with Elastic IPs
2. Configure target group pointing to Lambda
3. No ALB needed - simpler architecture

**Recommended: Option C for TouchNet UPay**

---

### 2.6 Alternative: Network Load Balancer with Lambda (Simplified)

**This is the recommended approach for TouchNet:**

1. **Create Target Group for Lambda:**
   - EC2 → Target Groups → Create
   - Target type: Lambda function
   - Name: `touchnet-lambda-tg`
   - Select Lambda function

2. **Create Network Load Balancer:**
   - EC2 → Load Balancers → Create
   - Type: **Network Load Balancer**
   - Name: `touchnet-proxy-nlb`
   - Scheme: Internet-facing
   - IP address type: IPv4
   - **Select subnets in 2+ AZs**

3. **Assign Elastic IPs:**
   - For each subnet/AZ, select "Use an Elastic IP address"
   - Choose the Elastic IPs you allocated earlier

4. **Configure Listener:**
   - Protocol: TCP
   - Port: 443
   - Default action: Forward to `touchnet-lambda-tg`

5. **Create NLB**

**Result:** Your NLB now has static IPs and routes to Lambda!

---

## Step 3: Configure SSL/TLS Certificate

### Option A: AWS Certificate Manager (ACM)

1. Navigate to **AWS Certificate Manager**
2. Click **Request a certificate**
3. Choose **Request a public certificate**
4. Enter domain name (e.g., `touchnet-proxy.yourdomain.com`)
5. Choose validation method (DNS recommended)
6. Complete validation
7. Attach certificate to your load balancer listener

### Option B: Import Existing Certificate

1. If you have an existing SSL certificate
2. Import it to ACM
3. Attach to load balancer

---

## Step 4: DNS Configuration

### 4.1 Create DNS Record

Point a friendly domain name to your load balancer:

1. In your DNS provider (Route 53, Cloudflare, etc.)
2. Create **A record** or **CNAME**:
   - Name: `touchnet-proxy.yourdomain.com`
   - Value: Your NLB DNS name (e.g., `touchnet-proxy-nlb-abc123.elb.us-east-1.amazonaws.com`)
   - Or if using A record with Elastic IPs, point to both IPs

**Example (Route 53):**
```
touchnet-proxy.yourdomain.com  →  A record  →  54.123.45.67
                                              →  54.123.45.68
```

---

## Step 5: Test the Proxy

### 5.1 Test from Local Machine

```bash
# Test proxy endpoint
curl -X POST https://touchnet-proxy.yourdomain.com/services/apexrest/upaypaymentreceive \
  -H "Content-Type: application/json" \
  -d '{
    "pmt_status": "success",
    "tpg_trans_id": "TEST123",
    "pmt_amt": "100.00",
    "pmt_date": "02/12/2026",
    "SEA_SECURE": "test-token"
  }'
```

**Expected Response:**
- If successful: `{"status":"success"}` or similar
- If error: Check Lambda CloudWatch logs

### 5.2 Check Lambda Logs

1. Navigate to **CloudWatch** → **Log groups**
2. Find log group: `/aws/lambda/touchnet-salesforce-proxy`
3. Check recent log streams for errors

---

## Step 6: Provide IPs to TouchNet

### 6.1 Gather Information

Collect the following for TouchNet:

1. **Static IP Addresses:**
   - Elastic IP 1: `54.123.45.67`
   - Elastic IP 2: `54.123.45.68`

2. **Proxy Endpoint URL:**
   - `https://touchnet-proxy.yourdomain.com/services/apexrest/upaypaymentreceive`

3. **Request Details:**
   - Protocol: HTTPS
   - Port: 443
   - Content-Type: application/x-www-form-urlencoded
   - Method: POST

---

### 6.2 Contact TouchNet

**Email Template:**

```
Subject: Static IP Whitelist Request for UPay Integration

Dear TouchNet Support,

We are implementing UPay integration for [Your Institution Name].

Please whitelist the following static IP addresses for our payment gateway integration:

Primary IP: 54.123.45.67
Secondary IP: 54.123.45.68

These IPs are associated with our proxy server that will receive POST callbacks from TouchNet UPay.

Integration Details:
- POST URL: https://touchnet-proxy.yourdomain.com/services/apexrest/upaypaymentreceive
- Protocol: HTTPS (Port 443)
- Institution: [Your Institution]
- UPay Site ID: [Your Site ID]

Please confirm when these IPs have been whitelisted.

Thank you,
[Your Name]
[Your Contact Info]
```

---

### 6.3 Wait for TouchNet Confirmation

- TouchNet typically processes whitelist requests within 1-3 business days
- They will confirm via email when IPs are whitelisted
- **Do not configure POST_LINK in TouchNet until IPs are whitelisted**

---

## Step 7: Update TouchNet Configuration

### 7.1 Configure POST_LINK

Once IPs are whitelisted:

1. Log into TouchNet UPay Admin Portal
2. Navigate to your UPay site configuration
3. Set **POST_LINK** to:
   ```
   https://touchnet-proxy.yourdomain.com/services/apexrest/upaypaymentreceive
   ```
4. **Do NOT use the Salesforce REST URL directly** - it won't work from TouchNet
5. Save configuration

---

## Monitoring and Maintenance

### CloudWatch Logs

**Monitor Lambda execution:**
- Log group: `/aws/lambda/touchnet-salesforce-proxy`
- Set up CloudWatch Alarms for errors
- Create dashboard for monitoring

**Metrics to track:**
- Invocations
- Errors
- Duration
- Throttles

### Cost Estimate

**Typical monthly costs (low volume):**
- Lambda: $0-5 (first 1M requests free)
- Load Balancer: $16-22/month (NLB)
- Elastic IPs: $3.60/month (if not attached)
- Data transfer: $0-10 (depends on volume)

**Total: ~$20-40/month**

---

## Troubleshooting

### Issue: TouchNet Can't Reach Proxy

**Check:**
1. Are Elastic IPs whitelisted by TouchNet?
2. Is NLB security group allowing inbound HTTPS?
3. Is SSL certificate valid?
4. Is Lambda function running?

**Test:**
```bash
curl -I https://touchnet-proxy.yourdomain.com
```

---

### Issue: Proxy Can't Reach Salesforce

**Check:**
1. Is Salesforce domain correct in Lambda code?
2. Is Salesforce REST endpoint deployed?
3. Are Lambda CloudWatch logs showing errors?

**Test Lambda → Salesforce:**
```javascript
// Add to Lambda code temporarily
console.log('Forwarding to:', options.hostname + options.path);
console.log('Request body:', JSON.stringify(body));
```

---

### Issue: SSL Certificate Errors

**Solutions:**
1. Ensure certificate matches domain name
2. Certificate must be valid and not expired
3. Use ACM for easier management
4. Check certificate chain is complete

---

## Security Best Practices

1. **Restrict NLB Security Group:**
   - Only allow HTTPS (443) from TouchNet IPs (if they provide them)
   - Block all other traffic

2. **Enable AWS WAF (Optional):**
   - Add Web Application Firewall to NLB
   - Protect against malicious requests

3. **Rotate Logs:**
   - Set CloudWatch log retention (7-30 days)
   - Archive important logs to S3

4. **Monitor Failed Requests:**
   - Set CloudWatch alarm for Lambda errors
   - Alert on-call engineer

5. **Use VPC Endpoints (Optional):**
   - Keep Lambda in VPC for added security
   - Use VPC endpoints to avoid internet routing

---

## Alternative: Using API Gateway Instead of Lambda + NLB

**Simpler architecture, but no static IPs:**

AWS API Gateway also doesn't provide static IPs by default. You would still need:
- Global Accelerator (for static IPs) → API Gateway → Lambda
- Or use NLB → Lambda (as documented above)

**Recommendation:** Stick with NLB + Lambda for simplicity and cost.

---

## Summary Checklist

- [ ] AWS account created and configured
- [ ] Lambda function deployed with updated Salesforce domain
- [ ] Elastic IPs allocated (2+ for high availability)
- [ ] Network Load Balancer created with Elastic IPs
- [ ] Target group linking NLB to Lambda
- [ ] SSL certificate configured
- [ ] DNS record pointing to NLB
- [ ] Proxy tested successfully
- [ ] Static IPs provided to TouchNet
- [ ] TouchNet confirms IPs are whitelisted
- [ ] POST_LINK updated in TouchNet to use proxy URL
- [ ] End-to-end payment tested

---

## Support

**AWS Issues:**
- AWS Support (if you have a support plan)
- AWS Documentation: https://docs.aws.amazon.com/lambda/

**TouchNet Issues:**
- TouchNet support representative
- Provide: UPay Site ID, static IPs, error logs

**Salesforce Issues:**
- Check Salesforce debug logs
- Review REST endpoint code
- Test REST endpoint directly (bypassing proxy)

---

**Last Updated:** February 12, 2026  
**Version:** 1.0

