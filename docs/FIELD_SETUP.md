# Manual Field Creation: UPay Site on Summit Events

## Overview

Since `summit__Summit_Events__c` is a **managed package object** from the Summit Events App, custom fields cannot be deployed via metadata. You must create the field manually in Setup.

## Step-by-Step Instructions

### 1. Navigate to Object Manager

1. In Setup, search for **"Object Manager"**
2. Find and click **"Summit Events"** (API Name: `summit__Summit_Events__c`)

### 2. Create Custom Field

1. Click the **"Fields & Relationships"** tab
2. Click **"New"** button
3. Select field type: **"Picklist"**
4. Click **"Next"**

### 3. Configure Field Details

Fill in the following values:

| Setting | Value |
|---------|-------|
| **Field Label** | `UPay Site` |
| **Field Name** | `UPay_Site` (will auto-generate API name: `UPay_Site__c`) |
| **Help Text** | `Select the TouchNet UPay site configuration to use for processing payments for this event. Sites are defined in Setup → Custom Metadata Types → TouchNet UPay Site.` |
| **Description** | `TouchNet UPay Site to use for payment processing. Maps to TouchNet_UPay_Site__mdt custom metadata records.` |

### 4. Configure Picklist Values

1. Select **"Use restricted picklist"** ✅
2. Add the following picklist values:

| Value | Label | Default? |
|-------|-------|----------|
| `Event_Registration` | Event Registration | ✅ Yes |

**Note:** Add additional values as you create more UPay site configurations in Custom Metadata. The picklist value should match the **DeveloperName** of your `TouchNet_UPay_Site__mdt` records.

### 5. Field-Level Security

1. Click **"Next"**
2. **Select all profiles** that need access (or at minimum):
   - System Administrator ✅
   - Summit Events Admin (if exists) ✅
3. Click **"Next"**

### 6. Add to Page Layouts

1. Select the page layouts where this field should appear
2. Recommended: Add to **all** Summit Events page layouts
3. Placement suggestion: Near the top of the page or in an "Event Settings" section
4. Click **"Save"**

## Verification

After creating the field:

1. Navigate to any Summit Events record
2. Verify the **"UPay Site"** field appears in the layout
3. Select a value from the picklist
4. Save the record

## How It Works

Once the field is created:

- **Payment Controller** will read the `UPay_Site__c` value from the Event record
- If the field exists and has a value, it uses that UPay site configuration
- If the field doesn't exist or is blank, it falls back to:
  1. URL parameter `?site=<sitename>` (backwards compatibility)
  2. Default value: `Event_Registration`

## Adding New UPay Sites

When you create a new UPay site in Custom Metadata:

1. Go to **Setup → Custom Metadata Types → TouchNet UPay Site → Manage Records → New**
2. Note the **DeveloperName** (e.g., `Application_Fee`)
3. Go to **Setup → Object Manager → Summit Events → Fields → UPay Site**
4. Click **"New"** next to Picklist Values
5. Add value matching the DeveloperName (e.g., `Application_Fee`)
6. Add a user-friendly label (e.g., `Application Fee`)
7. Save

## Troubleshooting

### Field Not Showing Up

**Cause:** Field not added to page layout  
**Solution:** Setup → Object Manager → Summit Events → Page Layouts → Edit layout → Add field

### "Invalid value" error when saving Event

**Cause:** Value in field doesn't match a picklist value  
**Solution:** Ensure the picklist contains a value matching your UPay site's DeveloperName

### Payment page shows error "Payment site configuration not found"

**Cause:** Picklist value doesn't match any `TouchNet_UPay_Site__mdt` record  
**Solution:** 
1. Check the Event record - what value is selected in UPay Site field?
2. Verify a Custom Metadata record exists with that exact DeveloperName
3. Verify the Custom Metadata record is marked as Active

---

**Related Documentation:**
- [SETUP_GUIDE.md](SETUP_GUIDE.md) - Complete setup instructions
- [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) - Technical details

