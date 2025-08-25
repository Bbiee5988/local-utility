import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.5.4/index.ts';
import { assertEquals } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
    name: "Verify core functionalities of local-vault contract",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const admin = accounts.get('wallet_1')!;
        const member = accounts.get('wallet_2')!;

        // Scenario: Resource Verification
        let block = chain.mineBlock([
            Tx.contractCall('local-vault', 'verify-resource', 
                ['u"resource-001"'], 
                deployer.address
            )
        ]);
        
        assertEquals(block.receipts[0].result, '(ok true)');

        // Scenario: Proposal Creation
        block = chain.mineBlock([
            Tx.contractCall('local-vault', 'create-proposal', 
                [
                    types.ascii('Community Resource Update'),
                    types.ascii('Proposal to enhance local resource management'),
                    types.uint(1000)
                ], 
                admin.address
            )
        ]);

        assertEquals(block.receipts[0].result.startsWith('(ok u'), true);
    }
});

Clarinet.test({
    name: "Test access control and permissions",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const admin = accounts.get('wallet_1')!;
        const member = accounts.get('wallet_2')!;

        // Scenario: Granting Resource Access
        let block = chain.mineBlock([
            Tx.contractCall('local-vault', 'grant-resource-access', 
                ['u"resource-002"', member.address], 
                admin.address
            )
        ]);

        assertEquals(block.receipts[0].result, '(ok true)');
    }
});