"use strict";

console.log('Loading function: touchnet-salesforce-default');

const querystring = require('node:querystring');
const https = require('https');

function postRequest(body) {
    const options = {
        hostname: 'salesforce-site-domain.my.site.com', // Replace with your Salesforce site domain where the Apex REST service is hosted
        path: '/services/apexrest/upaypaymentreceive', // Replace with the path to your Apex REST service. this path may be in a subdirectory, for example: '/subdir/services/apexrest/upaypaymentreceive'
        method: 'POST',
        port: 443,
        headers: {
            'Content-Type': 'application/json'
        },
    };

    return new Promise((resolve, reject) => {
        const req = https.request(options, res => {
            let rawData = '';

            res.on('data', chunk => {
                rawData += chunk;
            });

            res.on('end', () => {
                try {
                    resolve(JSON.parse(rawData));
                } catch (err) {
                    reject(new Error(err));
                }
            });
        });

        req.on('error', err => {
            reject(new Error(err));
        });

        req.write(JSON.stringify(body));
        req.end();
    });
}

exports.handler = async (event, context) => {
    try {

        //console.log('event:' + JSON.stringify(event));
        let eventBody = event.body;
        try {
            let buff = Buffer.from(eventBody, 'base64');
            eventBody = buff.toString('utf-8');
        } catch(e) {
            eventBody = event.body
        }

        //console.log('Decrypted body: ' + eventBody);

        eventBody = querystring.parse(eventBody);

        //console.log('JSON paresed data: '+ JSON.stringify(eventBody));

        const result = await postRequest(eventBody);
        //console.log('result is:️', result);

        if (result === "HTTP_ERROR") {
            return {
                "isBase64Encoded": false,
                "statusCode": 400,
                "statusDescription" : '400 ERROR',
                "headers": {
                    "Content-Type": "application/json"
                },
                "body": result
            };
        }

        return {
            "isBase64Encoded": false,
            "statusCode": 200,
            "statusDescription" : '200 OK',
            "headers": {
                "Content-Type": "application/json"
            },
            "body": result
        };

    } catch (error) {
        console.log('Error is:️', error);
        return {
            "isBase64Encoded": false,
            "statusCode": 500,
            "statusDescription" : '500 ERROR',
            "headers": {
                "Content-Type": "application/json"
            },
            "body": error.message
        };
    }
};
