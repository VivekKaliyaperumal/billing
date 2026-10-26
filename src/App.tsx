import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryCache, QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Routes, Route, Navigate, Outlet } from "react-router-dom";
import { Loader2 } from "lucide-react";
import { ProductProvider } from "./context/ProductContext";
import { SettingsProvider } from "./context/SettingsContext";
import { SalesHistoryProvider } from "./context/SalesHistoryContext";
import { CustomerProvider } from "./context/CustomerContext";
import { AuthProvider, useAuth } from "./context/AuthContext";
import { ThemeProvider } from "./components/ThemeProvider";
import { Header } from "./components/layout/Header";
import { toast } from "./hooks/use-toast";
import { ApiError, errorMessage } from "./lib/api/client";
import Index from "./pages/Index";
import AdminPage from "./pages/AdminPage";
import SettingsPage from "./pages/SettingsPage";
import SalesHistoryPage from "./pages/SalesHistoryPage";
import CustomersPage from "./pages/CustomersPage";
import LoginPage from "./pages/LoginPage";
import SignupPage from "./pages/SignupPage";
import NotFound from "./pages/NotFound";

const queryClient = new QueryClient({
  queryCache: new QueryCache({
    onError: (error) => {
      // An expired session is handled by AuthContext; everything else is shown once.
      if (error instanceof ApiError && error.status === 401) return;
      toast({ title: 'Could not load data', description: errorMessage(error), variant: 'destructive' });
    },
  }),
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      retry: (count, error) => !(error instanceof ApiError && error.status < 500 && error.status !== 0) && count < 2,
    },
  },
});

function FullPageSpinner() {
  return (
    <div className="flex min-h-screen items-center justify-center">
      <Loader2 className="h-8 w-8 animate-spin text-primary" />
    </div>
  );
}

/** Signed-in area: loads the shop's data and shows the app chrome. */
function RequireAuth() {
  const { status } = useAuth();
  if (status === 'loading') return <FullPageSpinner />;
  if (status === 'signedOut') return <Navigate to="/login" replace />;
  return (
    <SettingsProvider>
      <ProductProvider>
        <SalesHistoryProvider>
          <CustomerProvider>
            <div className="min-h-screen bg-background bg-pattern">
              <Header />
              <Outlet />
            </div>
          </CustomerProvider>
        </SalesHistoryProvider>
      </ProductProvider>
    </SettingsProvider>
  );
}

/** Product management is for the shop owner; cashiers go back to Sales. */
function RequireOwner() {
  const { isOwner } = useAuth();
  return isOwner ? <Outlet /> : <Navigate to="/" replace />;
}

/** Login and signup are only shown when signed out. */
function SignedOutOnly() {
  const { status } = useAuth();
  if (status === 'loading') return <FullPageSpinner />;
  if (status === 'signedIn') return <Navigate to="/" replace />;
  return (
    <div className="min-h-screen bg-background bg-pattern">
      <Outlet />
    </div>
  );
}

const App = () => (
  <QueryClientProvider client={queryClient}>
    <ThemeProvider defaultTheme="light" storageKey="shop-ui-theme">
      <TooltipProvider>
        <AuthProvider>
          <Toaster />
          <Sonner />
          <BrowserRouter>
            <Routes>
              <Route element={<SignedOutOnly />}>
                <Route path="/login" element={<LoginPage />} />
                <Route path="/signup" element={<SignupPage />} />
              </Route>
              <Route element={<RequireAuth />}>
                <Route path="/" element={<Index />} />
                <Route path="/history" element={<SalesHistoryPage />} />
                <Route path="/customers" element={<CustomersPage />} />
                <Route path="/settings" element={<SettingsPage />} />
                <Route element={<RequireOwner />}>
                  <Route path="/admin" element={<AdminPage />} />
                </Route>
              </Route>
              <Route path="*" element={<NotFound />} />
            </Routes>
          </BrowserRouter>
        </AuthProvider>
      </TooltipProvider>
    </ThemeProvider>
  </QueryClientProvider>
);

export default App;
