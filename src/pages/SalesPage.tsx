import { useState, useMemo } from 'react';
import { Search, Sparkles, UserPlus } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { ProductCard } from '@/components/products/ProductCard';
import { Cart } from '@/components/sales/Cart';
import { SaleReceipt } from '@/components/sales/SaleReceipt';
import { CreditCustomer, useProducts } from '@/context/ProductContext';
import { useCustomers } from '@/context/CustomerContext';
import { useSettings } from '@/context/SettingsContext';
import { CartItem, Product, Sale } from '@/types/product';
import { toast } from '@/hooks/use-toast';
import { ApiError, errorMessage } from '@/lib/api/client';
import { CartChange } from '@/lib/api/types';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Label } from '@/components/ui/label';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';

export default function SalesPage() {
  const { getMostUsedProducts, searchProducts, checkout, refreshProducts, products } = useProducts();
  const { customers } = useCustomers();
  const { formatPrice } = useSettings();
  const [busy, setBusy] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [cartItems, setCartItems] = useState<CartItem[]>([]);
  const [lastSale, setLastSale] = useState<Sale | null>(null);
  const [showReceipt, setShowReceipt] = useState(false);
  const [showCreditDialog, setShowCreditDialog] = useState(false);
  const [selectedCustomerId, setSelectedCustomerId] = useState<string>('');
  const [newCustomerName, setNewCustomerName] = useState('');
  const [newCustomerPhone, setNewCustomerPhone] = useState('');

  const displayedProducts = useMemo(() => {
    if (searchQuery.trim()) {
      return searchProducts(searchQuery);
    }
    return getMostUsedProducts(12);
  }, [searchQuery, getMostUsedProducts, searchProducts, products]);

  const handleSelectProduct = (product: Product) => {
    setCartItems(prev => {
      const existing = prev.find(item => item.product.id === product.id);
      
      if (existing) {
        const currentProduct = products.find(p => p.id === product.id);
        const maxStock = currentProduct?.stock || product.stock;
        
        if (existing.quantity >= maxStock) {
          toast({
            title: 'Stock limit reached',
            description: `Only ${maxStock} items available for ${product.name}`,
            variant: 'destructive',
          });
          return prev;
        }
        
        return prev.map(item =>
          item.product.id === product.id
            ? { ...item, quantity: item.quantity + 1 }
            : item
        );
      }
      
      return [...prev, { product, quantity: 1 }];
    });
  };

  const handleUpdateQuantity = (productId: string, quantity: number) => {
    if (quantity < 1) return;
    
    const currentProduct = products.find(p => p.id === productId);
    if (!currentProduct) return;
    
    if (quantity > currentProduct.stock) {
      toast({
        title: 'Stock limit reached',
        description: `Only ${currentProduct.stock} items available`,
        variant: 'destructive',
      });
      return;
    }
    
    setCartItems(prev =>
      prev.map(item =>
        item.product.id === productId ? { ...item, quantity } : item
      )
    );
  };

  const handleRemoveFromCart = (productId: string) => {
    setCartItems(prev => prev.filter(item => item.product.id !== productId));
  };

  /**
   * The server refused the cart because inventory changed (another counter
   * sold the stock, a price was edited, a product was removed). Bring the
   * cart in line with current inventory and let the cashier confirm again.
   */
  const repairCart = async (changes: CartChange[]) => {
    const latest = await refreshProducts().catch(() => products);
    setCartItems(prev =>
      prev.flatMap(item => {
        const current = latest.find(p => p.id === item.product.id);
        if (!current || current.stock <= 0) return [];
        return [{ product: current, quantity: Math.min(item.quantity, current.stock) }];
      })
    );
    toast({
      title: 'Cart updated — please review',
      description: changes.map(c => c.message).join('. '),
      variant: 'destructive',
    });
  };

  /** Runs a checkout; returns null if nothing was sold. */
  const runCheckout = async (customer?: CreditCustomer): Promise<Sale | null> => {
    setBusy(true);
    try {
      return await checkout(cartItems, customer);
    } catch (e) {
      if (e instanceof ApiError && e.code === 'cart_changed') {
        await repairCart((e.details.changes as CartChange[] | undefined) ?? []);
      } else {
        toast({ title: 'Sale not recorded', description: errorMessage(e), variant: 'destructive' });
      }
      return null;
    } finally {
      setBusy(false);
    }
  };

  const handleCheckout = async () => {
    if (cartItems.length === 0 || busy) return;

    const sale = await runCheckout();
    if (!sale) return;
    setLastSale(sale);
    setShowReceipt(true);
    setCartItems([]);

    toast({
      title: 'Sale completed!',
      description: `Total: ${formatPrice(sale.total)}`,
    });
  };

  const handleCreditSale = () => {
    if (cartItems.length === 0) return;
    setShowCreditDialog(true);
  };

  const handleConfirmCreditSale = async () => {
    if (busy) return;
    let customer: CreditCustomer | undefined;
    if (selectedCustomerId) {
      customer = { id: selectedCustomerId };
    } else if (newCustomerName.trim() && newCustomerPhone.trim()) {
      customer = { name: newCustomerName.trim(), phone: newCustomerPhone.trim() };
    }

    if (!customer) {
      toast({ title: 'Error', description: 'Please select or add a customer', variant: 'destructive' });
      return;
    }

    // Sale, stock, new customer and credit are saved together on the server.
    const sale = await runCheckout(customer);
    if (!sale) return;

    setLastSale(sale);
    setShowReceipt(true);
    setCartItems([]);
    setShowCreditDialog(false);
    setSelectedCustomerId('');
    setNewCustomerName('');
    setNewCustomerPhone('');

    toast({
      title: 'Credit sale recorded',
      description: `${formatPrice(sale.total)} added to customer credit`,
    });
  };

  const total = cartItems.reduce((sum, item) => sum + item.product.price * item.quantity, 0);

  return (
    <div className="container py-6">
      <div className="grid gap-6 lg:grid-cols-[1fr,420px]">
        {/* Products Section */}
        <div className="space-y-6">
          {/* Search Bar */}
          <div className="relative">
            <Search className="absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-muted-foreground" />
            <Input
              placeholder="Search products..."
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              className="h-14 pl-12 text-lg rounded-2xl border-border shadow-soft focus:shadow-medium transition-shadow"
            />
          </div>

          {/* Section Header */}
          <div className="flex items-center gap-2">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg gradient-accent">
              <Sparkles className="h-4 w-4 text-accent-foreground" />
            </div>
            <h2 className="font-display text-xl font-semibold text-foreground">
              {searchQuery ? 'Search Results' : 'Most Used Products'}
            </h2>
          </div>

          {/* Products Grid */}
          {displayedProducts.length === 0 ? (
            <div className="flex flex-col items-center justify-center rounded-2xl border-2 border-dashed border-border bg-card/50 p-12">
              <p className="text-muted-foreground">
                {searchQuery ? 'No products found' : 'No products available'}
              </p>
            </div>
          ) : (
            <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4">
              {displayedProducts.map(product => (
                <ProductCard
                  key={product.id}
                  product={product}
                  onSelect={handleSelectProduct}
                />
              ))}
            </div>
          )}
        </div>

        {/* Cart Section */}
        <div className="lg:sticky lg:top-24 lg:self-start">
          <Cart
            items={cartItems}
            onUpdateQuantity={handleUpdateQuantity}
            onRemove={handleRemoveFromCart}
            onCheckout={handleCheckout}
            onCreditSale={handleCreditSale}
          />
        </div>
      </div>

      {/* Receipt Modal */}
      <SaleReceipt
        sale={lastSale}
        open={showReceipt}
        onClose={() => setShowReceipt(false)}
      />

      {/* Credit Sale Dialog */}
      <Dialog open={showCreditDialog} onOpenChange={setShowCreditDialog}>
        <DialogContent className="bg-card border-border">
          <DialogHeader>
            <DialogTitle className="font-display flex items-center gap-2">
              <UserPlus className="h-5 w-5 text-accent" />
              Credit Sale - {formatPrice(total)}
            </DialogTitle>
          </DialogHeader>
          <div className="space-y-4 pt-4">
            <div className="space-y-2">
              <Label>Select Existing Customer</Label>
              <Select value={selectedCustomerId} onValueChange={setSelectedCustomerId}>
                <SelectTrigger className="h-12">
                  <SelectValue placeholder="Choose customer" />
                </SelectTrigger>
                <SelectContent className="bg-popover border-border">
                  {customers.map(c => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.name} - {c.phone}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            
            <div className="relative">
              <div className="absolute inset-0 flex items-center">
                <span className="w-full border-t border-border" />
              </div>
              <div className="relative flex justify-center text-xs uppercase">
                <span className="bg-card px-2 text-muted-foreground">Or add new</span>
              </div>
            </div>

            <div className="space-y-3">
              <Input
                value={newCustomerName}
                onChange={e => setNewCustomerName(e.target.value)}
                placeholder="Customer name"
                className="h-12"
                disabled={!!selectedCustomerId}
              />
              <Input
                value={newCustomerPhone}
                onChange={e => setNewCustomerPhone(e.target.value)}
                placeholder="Phone number"
                className="h-12"
                disabled={!!selectedCustomerId}
              />
            </div>

            <Button
              onClick={handleConfirmCreditSale}
              disabled={busy}
              className="w-full h-12 gradient-accent text-accent-foreground shadow-glow-accent"
            >
              Confirm Credit Sale
            </Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
